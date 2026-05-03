# frozen_string_literal: true

module DiscourseDigestMix
  class AdminController < ::Admin::AdminController
    requires_plugin "discourse-digest-mix"

    EDITABLE_SETTINGS = %w[
      digest_mix_enabled
      digest_mix_endpoint_url
      digest_mix_secret_header
      digest_mix_http_timeout
      digest_mix_email_type_split
      digest_mix_topic_type_split
      digest_mix_first_topic_split
      digest_mix_first_topic_split_enabled
      digest_mix_topic_type_registry
      digest_mix_promo_slot_count
      digest_mix_replace_within_top_n
      digest_mix_freshness_config
      digest_mix_product_weights
      digest_mix_regular_product_cooldown_sends
      digest_mix_regular_type_cooldown_sends
      digest_mix_regular_topic_dedup_sends
      digest_mix_push_cooldown_sends
      digest_mix_push_product_cooldown_sends
      digest_mix_push_topic_dedup_sends
      digest_mix_auto_campaign_cooldown_sends
      digest_mix_auto_campaign_product_cooldown_sends
      digest_mix_auto_campaign_topic_dedup_sends
      digest_mix_product_source
      digest_mix_mysql_host
      digest_mix_mysql_port
      digest_mix_mysql_db
      digest_mix_mysql_user
      digest_mix_mysql_password
      digest_mix_campaign_endpoint_url
      digest_mix_campaign_secret
    ].freeze

    def index
      settings = EDITABLE_SETTINGS.each_with_object({}) do |key, h|
        h[key] = SiteSetting.public_send(key)
      end
      render json: settings
    end

    def update
      params.permit!
      updated = {}

      EDITABLE_SETTINGS.each do |key|
        next unless params.key?(key)
        val = params[key]
        SiteSetting.set(key, val)
        updated[key] = val
      end

      render json: { success: true, updated: updated }
    rescue => e
      render json: { success: false, error: e.message }, status: 422
    end

    def active_products
      products = DigestMix::ProductResolver.active_products
      render json: { products: products }
    rescue => e
      render json: { products: [], error: e.message }, status: 500
    end
  end
end
