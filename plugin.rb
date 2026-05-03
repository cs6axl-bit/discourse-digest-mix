# frozen_string_literal: true
# name: discourse-digest-mix
# about: Budget-based digest injection with per-channel cooldowns, product weights, and visual admin UI
# version: 1.0.0
# authors: you

after_initialize do
  require_relative "lib/digest_mix/engine"
  require_relative "lib/digest_mix/cooldown_checker"
  require_relative "lib/digest_mix/history_writer"
  require_relative "lib/digest_mix/email_type_picker"
  require_relative "lib/digest_mix/slot_allocator"
  require_relative "lib/digest_mix/product_weighter"
  require_relative "lib/digest_mix/product_resolver"
  require_relative "lib/digest_mix/campaign_launcher"
  require_relative "lib/digest_mix/log_writer"
  require_relative "lib/digest_mix/webhook_sender"

  # ----------------------------------------------------------------
  # Hook into Topic.for_digest
  #
  # Uses a unique alias name (for_digest_before_mix) so this plugin
  # can coexist with discourse-promo-digest-injector when both are
  # installed. The call chain becomes:
  #   for_digest (this plugin) → for_digest_before_mix (old plugin or
  #   Discourse original) → Discourse original
  #
  # To switch active plugin:
  #   - Use new plugin: digest_mix_enabled = true,
  #                     promo_digest_injector_enabled = false
  #   - Use old plugin: digest_mix_enabled = false,
  #                     promo_digest_injector_enabled = true
  # No rebuild required — just flip the settings.
  # ----------------------------------------------------------------
  require_dependency "topic"

  class ::Topic
    class << self
      alias_method :for_digest_before_mix, :for_digest

      def for_digest(user, since, opts = {})
        base_proc = -> { for_digest_before_mix(user, since, opts) }
        DigestMix::Engine.process(user, since, opts, &base_proc)
      end
    end
  end

  # ----------------------------------------------------------------
  # Admin route
  # ----------------------------------------------------------------
  Discourse::Application.routes.append do
    namespace :discourse_digest_mix, path: "/digest-mix" do
      get  "settings"       => "admin#index"
      post "settings"       => "admin#update"
      get  "active_products" => "admin#active_products"
    end
  end
end

# ----------------------------------------------------------------
# Assets
# ----------------------------------------------------------------
register_asset "javascripts/discourse/routes/admin-plugins-digest-mix.js"
register_asset "javascripts/discourse/controllers/admin-plugins-digest-mix.js"
register_asset "javascripts/discourse/components/digest-mix-split-bar.js"
register_asset "javascripts/discourse/components/digest-mix-split-bar.hbs", :server_side
register_asset "javascripts/discourse/components/digest-mix-product-weights.js"
register_asset "javascripts/discourse/components/digest-mix-product-weights.hbs", :server_side
register_asset "javascripts/discourse/templates/admin/plugins-digest-mix.hbs", :server_side

add_admin_route "digest_mix.admin.title", "digest-mix"
