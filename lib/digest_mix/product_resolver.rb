# frozen_string_literal: true

module DigestMix
  module ProductResolver

    # Returns { topic_id => { product_name:, topic_type: } }
    def self.resolve_batch(topic_ids)
      return {} if topic_ids.blank?

      if SiteSetting.digest_mix_product_source == "local"
        resolve_local(topic_ids)
      else
        resolve_mysql(topic_ids)
      end
    rescue => e
      Rails.logger.error("[discourse-digest-mix] ProductResolver error: #{e.message}")
      {}
    end

    # Returns array of { "id" => .., "name" => .. }
    def self.active_products
      if SiteSetting.digest_mix_product_source == "local"
        active_products_local
      else
        active_products_mysql
      end
    rescue => e
      Rails.logger.error("[discourse-digest-mix] ProductResolver#active_products error: #{e.message}")
      []
    end

    # ----------------------------------------------------------------
    private

    # Phase B — tables in local Discourse Postgres DB
    def self.resolve_local(topic_ids)
      result = {}

      # Each source table maps to a topic_type. Adjust table/column names as needed.
      sources = [
        { table: "aiwrites_hardsale_posts_publish_log",       type: "hardsale",    topic_col: "discourse_topic_id", product_col: "promo_product_name" },
        { table: "aiwrites_masterpromo_published_promo_posts", type: "masterpromo", topic_col: "discourse_topic_id", product_col: "promo_product" },
        { table: "aiwrites_promofocused_published_promo_posts",type: "promofocused",topic_col: "discourse_topic_id", product_col: "promo_product" },
        { table: "aiwrites_superpromo_published_promo_posts",  type: "superpromo",  topic_col: "discourse_topic_id", product_col: "promo_product" },
      ]

      sources.each do |src|
        rows = ActiveRecord::Base.connection.execute(
          "SELECT #{src[:topic_col]} AS tid, #{src[:product_col]} AS pname
           FROM #{src[:table]}
           WHERE #{src[:topic_col]} IN (#{topic_ids.map(&:to_i).join(',')})"
        )
        rows.each do |row|
          tid = row["tid"].to_i
          result[tid] ||= { product_name: row["pname"].to_s, topic_type: src[:type] }
        end
      end

      result
    end

    def self.active_products_local
      ActiveRecord::Base.connection
        .execute("SELECT id, name FROM products WHERE isactive = 1")
        .map { |r| { "id" => r["id"], "name" => r["name"] } }
    end

    # Phase A — external MySQL
    def self.resolve_mysql(topic_ids)
      result = {}
      conn   = mysql_connection

      sources = [
        { table: "aiwrites_hardsale_posts_publish_log",       type: "hardsale",    topic_col: "discourse_topic_id", product_col: "promo_product_name" },
        { table: "aiwrites_masterpromo_published_promo_posts", type: "masterpromo", topic_col: "discourse_topic_id", product_col: "promo_product" },
        { table: "aiwrites_promofocused_published_promo_posts",type: "promofocused",topic_col: "discourse_topic_id", product_col: "promo_product" },
        { table: "aiwrites_superpromo_published_promo_posts",  type: "superpromo",  topic_col: "discourse_topic_id", product_col: "promo_product" },
      ]

      ids_sql = topic_ids.map(&:to_i).join(",")

      sources.each do |src|
        conn.query(
          "SELECT #{src[:topic_col]} AS tid, #{src[:product_col]} AS pname
           FROM #{src[:table]}
           WHERE #{src[:topic_col]} IN (#{ids_sql})"
        ).each do |row|
          tid = row["tid"].to_i
          result[tid] ||= { product_name: row["pname"].to_s, topic_type: src[:type] }
        end
      end

      result
    ensure
      conn&.close
    end

    def self.active_products_mysql
      conn = mysql_connection
      conn.query("SELECT id, name FROM products WHERE isactive = 1")
          .map { |r| { "id" => r["id"], "name" => r["name"] } }
    ensure
      conn&.close
    end

    def self.mysql_connection
      require "mysql2"
      Mysql2::Client.new(
        host:     SiteSetting.digest_mix_mysql_host,
        port:     SiteSetting.digest_mix_mysql_port.to_i,
        database: SiteSetting.digest_mix_mysql_db,
        username: SiteSetting.digest_mix_mysql_user,
        password: SiteSetting.digest_mix_mysql_password,
        reconnect: true,
      )
    end
  end
end
