# frozen_string_literal: true

module DigestMix
  module HistoryWriter
    def self.record(user, final_list, email_type, injected_slots)
      now = Time.now.utc

      rows = injected_slots.map do |slot|
        {
          user_id:       user.id,
          topic_id:      slot[:topic_id],
          email_type:    email_type,
          topic_type:    slot[:topic_type],
          product_name:  slot[:product_name],
          was_first_topic: slot[:slot_index] == 0,
          sent_at:       now,
          created_at:    now,
          updated_at:    now,
        }
      end

      # For push/campaign with no injected_slots detail, record just the email type
      if rows.empty? && final_list.present?
        rows << {
          user_id:        user.id,
          topic_id:       final_list.first&.id,
          email_type:     email_type,
          topic_type:     nil,
          product_name:   nil,
          was_first_topic: true,
          sent_at:        now,
          created_at:     now,
          updated_at:     now,
        }
      end

      DigestMixUserHistory.insert_all(rows) if rows.any?
    rescue => e
      Rails.logger.error("[discourse-digest-mix] HistoryWriter error: #{e.message}")
    end
  end
end
