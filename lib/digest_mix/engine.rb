# frozen_string_literal: true

module DigestMix
  module Engine
    PLUGIN_NAME = "discourse-digest-mix"

    def self.process(user, since, opts, &base_proc)
      return base_proc.call unless SiteSetting.digest_mix_enabled
      return base_proc.call unless real_digest_call?(opts)

      base_list = base_proc.call
      return base_list if base_list.blank?

      begin
        run(user, since, base_list)
      rescue => e
        Rails.logger.error("[#{PLUGIN_NAME}] Engine error for user #{user.id}: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        base_list
      end
    end

    def self.run(user, since, base_list)
      registry    = load_registry
      tag_ids_map = build_tag_ids_map(registry)

      # Pre-scan: separate promo topics Discourse naturally picked
      promo_in_base, non_promo_in_base = scan_base_list(base_list, tag_ids_map)

      email_type = EmailTypePicker.pick(user)

      context = {
        user:              user,
        email_type:        email_type,
        registry:          registry,
        tag_ids_map:       tag_ids_map,
        promo_in_base:     promo_in_base,
        non_promo_in_base: non_promo_in_base,
        base_list:         base_list,
      }

      final_list, injected_slots, skips =
        case email_type
        when "push"
          SlotAllocator.pick_push(context)
        when "auto_campaign"
          CampaignLauncher.launch(context)
        else
          SlotAllocator.fill_slots(context)
        end

      return base_list if final_list.blank?

      HistoryWriter.record(user, final_list, email_type, injected_slots)
      LogWriter.write(user, base_list, final_list, promo_in_base, injected_slots, email_type, skips)
      WebhookSender.enqueue(user, build_payload(context, final_list, injected_slots, skips))

      final_list
    end

    # ----------------------------------------------------------------
    # Helpers
    # ----------------------------------------------------------------

    def self.real_digest_call?(opts)
      opts[:top_order] == true && opts[:limit].present?
    end

    def self.load_registry
      JSON.parse(SiteSetting.digest_mix_topic_type_registry)
    rescue
      []
    end

    def self.build_tag_ids_map(registry)
      registry.each_with_object({}) do |type_def, map|
        tags = Array(type_def["tags"]).map(&:downcase)
        ids  = Tag.where("LOWER(name) IN (?)", tags).pluck(:id)
        map[type_def["id"]] = ids
      end
    end

    def self.scan_base_list(base_list, tag_ids_map)
      return [[], base_list] if base_list.blank? || tag_ids_map.blank?

      all_promo_tag_ids = tag_ids_map.values.flatten.uniq
      topic_ids = base_list.map(&:id)

      promo_topic_ids = TopicTag
        .where(topic_id: topic_ids, tag_id: all_promo_tag_ids)
        .pluck(:topic_id)
        .to_set

      promo_in_base     = base_list.select { |t| promo_topic_ids.include?(t.id) }
      non_promo_in_base = base_list.reject { |t| promo_topic_ids.include?(t.id) }

      [promo_in_base, non_promo_in_base]
    end

    def self.build_payload(context, final_list, injected_slots, skips)
      {
        user_id:              context[:user].id,
        email:                context[:user].email,
        datetime_utc:         Time.now.utc.iso8601,
        email_type:           context[:email_type],
        injected_topics:      injected_slots,
        final_topic_ids:      final_list.map(&:id),
        skips:                skips,
        email_type_split_used: JSON.parse(SiteSetting.digest_mix_email_type_split),
        topic_type_split_used: JSON.parse(SiteSetting.digest_mix_topic_type_split),
      }
    end
  end
end
