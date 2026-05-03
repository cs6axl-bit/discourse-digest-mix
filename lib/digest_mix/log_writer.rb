# frozen_string_literal: true

module DigestMix
  module LogWriter
    def self.write(user, base_list, final_list, promo_found_in_base, injected_slots, email_type, skips)
      DigestMixSendLog.create!(
        user_id:            user.id,
        user_email:         user.email,
        email_type:         email_type,
        final_topic_ids:    final_list.map(&:id).to_json,
        injected_slots:     injected_slots.to_json,
        base_topic_ids:     base_list.map(&:id).to_json,
        promo_found_in_base: promo_found_in_base.map(&:id).to_json,
        cooldowns_applied:  {}.to_json,
        freshness_applied:  {}.to_json,
        skips:              skips.to_json,
        webhook_sent:       false,
        sent_at:            Time.now.utc,
      )
    rescue => e
      Rails.logger.error("[discourse-digest-mix] LogWriter error: #{e.message}")
    end

    def self.mark_webhook_sent(log_id, status_code)
      DigestMixSendLog.where(id: log_id).update_all(webhook_sent: true, webhook_status: status_code)
    rescue
      nil
    end
  end
end
