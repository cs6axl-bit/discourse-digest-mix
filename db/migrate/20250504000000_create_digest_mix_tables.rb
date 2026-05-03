# frozen_string_literal: true

class CreateDigestMixTables < ActiveRecord::Migration[7.0]
  def change
    create_table :digest_mix_user_history do |t|
      t.integer  :user_id,        null: false
      t.integer  :topic_id
      t.string   :email_type,     null: false
      t.string   :topic_type
      t.string   :product_name
      t.boolean  :was_first_topic, default: false
      t.datetime :sent_at,        null: false
      t.timestamps
    end

    add_index :digest_mix_user_history, [:user_id, :sent_at]
    add_index :digest_mix_user_history, [:user_id, :email_type, :sent_at],
              name: "idx_dmuh_user_channel_sent"
    add_index :digest_mix_user_history, [:user_id, :product_name]
    add_index :digest_mix_user_history, [:user_id, :topic_type]

    create_table :digest_mix_send_logs do |t|
      t.integer  :user_id,           null: false
      t.string   :user_email
      t.string   :email_type,        null: false
      t.text     :final_topic_ids
      t.text     :injected_slots
      t.text     :base_topic_ids
      t.text     :promo_found_in_base
      t.text     :cooldowns_applied
      t.text     :freshness_applied
      t.text     :skips
      t.boolean  :webhook_sent,      default: false
      t.integer  :webhook_status
      t.datetime :sent_at,           null: false
      t.timestamps
    end

    add_index :digest_mix_send_logs, [:user_id, :sent_at]
    add_index :digest_mix_send_logs, :sent_at
    add_index :digest_mix_send_logs, :email_type
  end
end
