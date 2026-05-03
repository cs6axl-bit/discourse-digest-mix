# frozen_string_literal: true

module DigestMix
  module CooldownChecker

    # Returns a Set of topic_ids the user received on this channel
    # within the last N sends on that channel.
    def self.topics_in_dedup_window(user, channel:)
      n = dedup_sends_for(channel)
      return Set.new if n.zero?

      DigestMixUserHistory
        .where(user_id: user.id, email_type: channel)
        .where.not(topic_id: nil)
        .order(sent_at: :desc)
        .limit(n)
        .pluck(:topic_id)
        .to_set
    end

    # Returns an array of product_names the user received on this channel
    # within the last N sends on that channel.
    def self.products_in_cooldown(user, channel:)
      n = product_cooldown_sends_for(channel)
      return [] if n.zero?

      DigestMixUserHistory
        .where(user_id: user.id, email_type: channel)
        .order(sent_at: :desc)
        .limit(n)
        .pluck(:product_name)
        .compact
        .uniq
    end

    # Returns a float weight modifier for a topic type in regular digests.
    # 0.0 = blocked, 0.5 = halved, 1.0 = full weight.
    def self.type_weight_modifier(user, topic_type)
      n = SiteSetting.digest_mix_regular_type_cooldown_sends
      return 1.0 if n.zero?

      recent_types = DigestMixUserHistory
        .where(user_id: user.id, email_type: "regular")
        .order(sent_at: :desc)
        .limit(n)
        .pluck(:topic_type)

      count = recent_types.count(topic_type)
      return 1.0 if count.zero?
      count == 1 ? 0.5 : 0.0
    end

    # Returns true if push is on cooldown.
    # Push is in cooldown if a push appears in the user's last N sends (any channel).
    def self.push_in_cooldown?(user)
      n = SiteSetting.digest_mix_push_cooldown_sends
      return false if n.zero?

      recent = DigestMixUserHistory
        .where(user_id: user.id)
        .order(sent_at: :desc)
        .limit(n)
        .pluck(:email_type)

      recent.include?("push")
    end

    # Returns true if auto_campaign is on cooldown.
    # Campaign is in cooldown if a campaign appears in the last N campaign sends.
    def self.auto_campaign_in_cooldown?(user)
      n = SiteSetting.digest_mix_auto_campaign_cooldown_sends
      return false if n.zero?

      DigestMixUserHistory
        .where(user_id: user.id, email_type: "auto_campaign")
        .order(sent_at: :desc)
        .limit(1)
        .exists?
        .tap do |exists|
          return false unless exists
          # Check if N campaigns have passed since the last one
          total = DigestMixUserHistory
            .where(user_id: user.id, email_type: "auto_campaign")
            .count
          last_n_types = DigestMixUserHistory
            .where(user_id: user.id)
            .order(sent_at: :desc)
            .limit(n)
            .pluck(:email_type)
          return last_n_types.include?("auto_campaign")
        end
    end

    # ----------------------------------------------------------------
    private

    def self.dedup_sends_for(channel)
      case channel
      when "regular"       then SiteSetting.digest_mix_regular_topic_dedup_sends
      when "push"          then SiteSetting.digest_mix_push_topic_dedup_sends
      when "auto_campaign" then SiteSetting.digest_mix_auto_campaign_topic_dedup_sends
      else 0
      end
    end

    def self.product_cooldown_sends_for(channel)
      case channel
      when "regular"       then SiteSetting.digest_mix_regular_product_cooldown_sends
      when "push"          then SiteSetting.digest_mix_push_product_cooldown_sends
      when "auto_campaign" then SiteSetting.digest_mix_auto_campaign_product_cooldown_sends
      else 0
      end
    end
  end
end
