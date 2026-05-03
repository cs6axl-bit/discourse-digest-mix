# frozen_string_literal: true

module DigestMix
  module WebhookSender
    def self.enqueue(user, payload)
      return if SiteSetting.digest_mix_endpoint_url.blank?

      Jobs.enqueue(:digest_mix_send_webhook, user_id: user.id, payload: payload)
    end
  end
end

# ----------------------------------------------------------------
# Sidekiq job
# ----------------------------------------------------------------
module ::Jobs
  class DigestMixSendWebhook < ::Jobs::Base
    sidekiq_options retry: 2

    def execute(args)
      url = SiteSetting.digest_mix_endpoint_url
      return if url.blank?

      payload = args[:payload].is_a?(String) ? JSON.parse(args[:payload]) : args[:payload]

      uri  = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl       = uri.scheme == "https"
      http.open_timeout  = SiteSetting.digest_mix_http_timeout.to_i
      http.read_timeout  = SiteSetting.digest_mix_http_timeout.to_i

      req = Net::HTTP::Post.new(uri.path.presence || "/")
      req["Content-Type"]           = "application/json"
      req["X-Digest-Mix-Secret"]    = SiteSetting.digest_mix_secret_header
      req.body = payload.to_json

      response = http.request(req)

      Rails.logger.info("[discourse-digest-mix] Webhook → #{response.code} for user #{args[:user_id]}")
    rescue => e
      Rails.logger.error("[discourse-digest-mix] WebhookSender job failed: #{e.message}")
      raise
    end
  end
end
