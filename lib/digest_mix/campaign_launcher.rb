# frozen_string_literal: true

module DigestMix
  module CampaignLauncher

    # Picks a campaign topic, launches the campaign, returns [final_list, injected_slots, skips]
    def self.launch(context)
      user        = context[:user]
      email_type  = "auto_campaign"
      registry    = context[:registry]
      tag_ids_map = context[:tag_ids_map]
      guardian    = Guardian.new(user)

      deduped_ids     = CooldownChecker.topics_in_dedup_window(user, channel: email_type)
      cooled_products = CooldownChecker.products_in_cooldown(user, channel: email_type)

      # Build candidate pool across all types
      pool = []
      registry.each do |type_def|
        type_id = type_def["id"]
        tag_ids = tag_ids_map[type_id]
        next if tag_ids.blank?

        ids = TopicTag.where(tag_id: tag_ids).distinct.pluck(:topic_id)
        next if ids.empty?

        visible = Topic.visible.secured(guardian).where(id: ids).where.not(id: deduped_ids.to_a).pluck(:id)
        visible.each { |tid| pool << { topic_id: tid, topic_type: type_id } }
      end

      pool_ids     = pool.map { |c| c[:topic_id] }
      product_map  = ProductResolver.resolve_batch(pool_ids)
      pool.each { |c| c[:product_name] = product_map.dig(c[:topic_id], :product_name) }
      pool.reject! { |c| cooled_products.include?(c[:product_name]) }

      if pool.empty?
        return [context[:non_promo_in_base], [], [{ reason: "no_campaign_candidate" }]]
      end

      chosen = pool.sample
      topic  = Topic.find_by(id: chosen[:topic_id])
      return [context[:non_promo_in_base], [], [{ reason: "topic_not_found" }]] if topic.nil?

      # Fire campaign endpoint
      fire_campaign(user, topic, chosen[:product_name])

      slot = {
        topic_id:    topic.id,
        topic_type:  chosen[:topic_type],
        product_name: chosen[:product_name],
        slot_index:  0,
        was_first:   true,
      }
      [[topic], [slot], []]
    rescue => e
      Rails.logger.error("[discourse-digest-mix] CampaignLauncher error: #{e.message}")
      [context[:non_promo_in_base], [], [{ reason: "campaign_error", message: e.message }]]
    end

    # ----------------------------------------------------------------
    private

    def self.fire_campaign(user, topic, product_name)
      url = SiteSetting.digest_mix_campaign_endpoint_url
      return if url.blank?

      payload = {
        user_id:      user.id,
        email:        user.email,
        topic_id:     topic.id,
        product_name: product_name,
        triggered_at: Time.now.utc.iso8601,
      }

      uri     = URI.parse(url)
      http    = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 3
      http.read_timeout = 5

      req = Net::HTTP::Post.new(uri.path.presence || "/")
      req["Content-Type"]              = "application/json"
      req["X-Digest-Mix-Campaign-Secret"] = SiteSetting.digest_mix_campaign_secret
      req.body = payload.to_json

      http.request(req)
    rescue => e
      Rails.logger.warn("[discourse-digest-mix] CampaignLauncher#fire_campaign failed: #{e.message}")
    end
  end
end
