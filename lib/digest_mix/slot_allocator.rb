# frozen_string_literal: true

module DigestMix
  module SlotAllocator

    # ----------------------------------------------------------------
    # Regular digest: fill N promo slots, return [final_list, injected_slots, skips]
    # ----------------------------------------------------------------
    def self.fill_slots(context)
      user              = context[:user]
      registry          = context[:registry]
      tag_ids_map       = context[:tag_ids_map]
      promo_in_base     = context[:promo_in_base]
      non_promo_in_base = context[:non_promo_in_base]
      email_type        = context[:email_type]

      slot_count  = SiteSetting.digest_mix_promo_slot_count
      top_n       = SiteSetting.digest_mix_replace_within_top_n
      guardian    = Guardian.new(user)

      # Pre-load cooldown data (one query each)
      deduped_ids      = CooldownChecker.topics_in_dedup_window(user, channel: email_type)
      cooled_products  = CooldownChecker.products_in_cooldown(user, channel: email_type)

      # Full candidate pool = all eligible promo topics for this user
      # (promo_in_base topics join the pool; no preference)
      candidate_pool = build_candidate_pool(
        user, registry, tag_ids_map, guardian,
        deduped_ids, cooled_products, promo_in_base
      )

      # Resolve product names for the pool in one batch
      pool_topic_ids = candidate_pool.map { |c| c[:topic].id }
      product_map    = ProductResolver.resolve_batch(pool_topic_ids)
      candidate_pool.each { |c| c[:product_name] = product_map.dig(c[:topic].id, :product_name) }

      # Re-apply product cooldown now that we have product names
      candidate_pool.reject! { |c| cooled_products.include?(c[:product_name]) }

      type_split_raw = parse_split(SiteSetting.digest_mix_topic_type_split)
      first_split    = SiteSetting.digest_mix_first_topic_split_enabled ?
                         parse_split(SiteSetting.digest_mix_first_topic_split) :
                         type_split_raw

      freshness_cfg = load_freshness_config
      last_digest_at = last_digest_sent_at(user)

      injected_slots = []
      used_topic_ids = Set.new
      skips          = []

      slot_count.times do |slot_index|
        split = slot_index == 0 ? first_split : type_split_raw

        # Apply type-level soft cooldown
        effective_split = apply_type_cooldown(split, user)
        effective_split = normalize(effective_split)
        next(skips << { slot: slot_index, reason: "no_eligible_type" }) if effective_split.empty?

        topic, type_id, skip_reason = pick_topic_for_slot(
          candidate_pool, effective_split, freshness_cfg, last_digest_at, used_topic_ids
        )

        if topic.nil?
          skips << { slot: slot_index, reason: skip_reason || "no_candidates" }
          next
        end

        product_name = product_map.dig(topic.id, :product_name)
        injected_slots << {
          topic_id:    topic.id,
          topic_type:  type_id,
          product_name: product_name,
          slot_index:  slot_index,
          was_first:   slot_index == 0,
        }
        used_topic_ids.add(topic.id)
      end

      final_list = compose_final_list(injected_slots, non_promo_in_base, top_n, slot_count)
      [final_list, injected_slots, skips]
    end

    # ----------------------------------------------------------------
    # Push: pick one topic, return [final_list, injected_slots, skips]
    # ----------------------------------------------------------------
    def self.pick_push(context)
      user         = context[:user]
      registry     = context[:registry]
      tag_ids_map  = context[:tag_ids_map]
      email_type   = "push"
      guardian     = Guardian.new(user)

      deduped_ids     = CooldownChecker.topics_in_dedup_window(user, channel: email_type)
      cooled_products = CooldownChecker.products_in_cooldown(user, channel: email_type)

      candidate_pool = build_candidate_pool(
        user, registry, tag_ids_map, guardian,
        deduped_ids, cooled_products, []
      )

      pool_topic_ids = candidate_pool.map { |c| c[:topic].id }
      product_map    = ProductResolver.resolve_batch(pool_topic_ids)
      candidate_pool.each { |c| c[:product_name] = product_map.dig(c[:topic].id, :product_name) }
      candidate_pool.reject! { |c| cooled_products.include?(c[:product_name]) }

      first_split    = parse_split(SiteSetting.digest_mix_first_topic_split)
      effective_split = normalize(first_split)
      freshness_cfg  = load_freshness_config
      last_digest_at = last_digest_sent_at(user)

      topic, type_id, _ = pick_topic_for_slot(
        candidate_pool, effective_split, freshness_cfg, last_digest_at, Set.new
      )

      return [context[:non_promo_in_base], [], [{ reason: "no_push_candidate" }]] if topic.nil?

      product_name = product_map.dig(topic.id, :product_name)
      slot = { topic_id: topic.id, topic_type: type_id, product_name: product_name, slot_index: 0, was_first: true }
      [[topic], [slot], []]
    end

    # ----------------------------------------------------------------
    private
    # ----------------------------------------------------------------

    def self.build_candidate_pool(user, registry, tag_ids_map, guardian, deduped_ids, _cooled_products, extra_topics)
      pool = []

      registry.each do |type_def|
        type_id  = type_def["id"]
        tag_ids  = tag_ids_map[type_id]
        next if tag_ids.blank?

        topic_ids = TopicTag
          .where(tag_id: tag_ids)
          .distinct
          .pluck(:topic_id)

        next if topic_ids.empty?

        visible_ids = Topic
          .visible
          .secured(guardian)
          .where(id: topic_ids)
          .where.not(id: deduped_ids.to_a)
          .pluck(:id)
          .to_set

        visible_ids.each do |tid|
          pool << { topic: OpenStruct.new(id: tid), topic_type: type_id, product_name: nil }
        end
      end

      # Add extra (promo_in_base) topics if not already present
      existing_ids = pool.map { |c| c[:topic].id }.to_set
      extra_topics.each do |t|
        next if existing_ids.include?(t.id)
        next if deduped_ids.include?(t.id)
        type_id = detect_type(t.id, tag_ids_map)
        next if type_id.nil?
        pool << { topic: t, topic_type: type_id, product_name: nil }
      end

      pool
    end

    def self.detect_type(topic_id, tag_ids_map)
      tag_ids = TopicTag.where(topic_id: topic_id).pluck(:tag_id).to_set
      tag_ids_map.each do |type_id, ids|
        return type_id if ids.any? { |id| tag_ids.include?(id) }
      end
      nil
    end

    def self.pick_topic_for_slot(pool, split, freshness_cfg, last_digest_at, used_ids)
      # Try types in weighted order, with fallback relaxation
      ordered_types = weighted_order(split)

      ordered_types.each do |type_id|
        candidates = pool.select do |c|
          c[:topic_type] == type_id &&
            !used_ids.include?(c[:topic].id) &&
            passes_freshness?(c[:topic].id, type_id, freshness_cfg, last_digest_at)
        end

        topic = ProductWeighter.pick(candidates, type_id)
        return [topic, type_id, nil] if topic
      end

      # Freshness fallback: relax max_age_days
      ordered_types.each do |type_id|
        candidates = pool.select do |c|
          c[:topic_type] == type_id &&
            !used_ids.include?(c[:topic].id) &&
            passes_freshness_relaxed?(c[:topic].id, type_id, freshness_cfg, last_digest_at)
        end

        topic = ProductWeighter.pick(candidates, type_id)
        return [topic, type_id, "relaxed_max_age"] if topic
      end

      # Full fallback: any type, no freshness
      ordered_types.each do |type_id|
        candidates = pool.select { |c| c[:topic_type] == type_id && !used_ids.include?(c[:topic].id) }
        topic = ProductWeighter.pick(candidates, type_id)
        return [topic, type_id, "relaxed_all_freshness"] if topic
      end

      [nil, nil, "no_candidates"]
    end

    def self.passes_freshness?(topic_id, type_id, freshness_cfg, last_digest_at)
      cfg = freshness_cfg[type_id]
      return true if cfg.nil?

      created_at = Topic.where(id: topic_id).pick(:created_at)
      return false if created_at.nil?

      if cfg["max_age_days"].to_i > 0
        return false if created_at < cfg["max_age_days"].to_i.days.ago
      end

      if cfg["require_after_last_digest"] && last_digest_at
        return false if created_at <= last_digest_at
      end

      true
    end

    def self.passes_freshness_relaxed?(topic_id, type_id, freshness_cfg, last_digest_at)
      cfg = freshness_cfg[type_id]
      return true if cfg.nil?
      return true unless cfg["require_after_last_digest"] && last_digest_at

      created_at = Topic.where(id: topic_id).pick(:created_at)
      return false if created_at.nil?
      created_at > last_digest_at
    end

    def self.apply_type_cooldown(split, user)
      split.each_with_object({}) do |(type_id, weight), h|
        modifier = CooldownChecker.type_weight_modifier(user, type_id)
        h[type_id] = weight * modifier
      end
    end

    def self.compose_final_list(injected_slots, non_promo_in_base, top_n, slot_count)
      # Build ordered list: inject promo topics at the front (within top_n),
      # fill remaining positions from non_promo_in_base
      total_needed = [top_n, non_promo_in_base.length + slot_count].min

      injected_topic_ids = injected_slots.map { |s| s[:topic_id] }

      # Fetch actual Topic objects for injected ids
      injected_topics = Topic.where(id: injected_topic_ids).index_by(&:id)

      result = []
      injected_slots.each do |slot|
        t = injected_topics[slot[:topic_id]]
        result << t if t
      end

      non_promo_in_base.each do |t|
        result << t
        break if result.length >= total_needed
      end

      result
    end

    def self.last_digest_sent_at(user)
      DigestMixUserHistory
        .where(user_id: user.id)
        .order(sent_at: :desc)
        .limit(1)
        .pick(:sent_at) ||
        UserStat.where(user_id: user.id).pick(:digest_attempted_at)
    rescue
      nil
    end

    def self.parse_split(json)
      JSON.parse(json).transform_keys(&:to_s).transform_values(&:to_f)
    rescue
      {}
    end

    def self.normalize(split)
      total = split.values.sum.to_f
      return {} if total.zero?
      split.select { |_, v| v > 0 }.transform_values { |v| v / total * 100.0 }
    end

    def self.weighted_order(split)
      split.sort_by { |_, w| -w }.map(&:first)
    end

    def self.load_freshness_config
      JSON.parse(SiteSetting.digest_mix_freshness_config)
    rescue
      {}
    end
  end
end
