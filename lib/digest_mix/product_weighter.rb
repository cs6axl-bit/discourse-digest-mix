# frozen_string_literal: true

module DigestMix
  module ProductWeighter

    # Given a list of candidate topic structs (each responding to #id and
    # having product_name resolved), perform a weighted random pick.
    # candidates: Array of { topic:, product_name: }
    # type_id: string topic type id
    # Returns the selected topic object, or nil.
    def self.pick(candidates, type_id)
      return nil if candidates.empty?

      weights_config = load_weights(type_id)

      # Assign weight to each candidate based on its product
      weighted = candidates.map do |c|
        w = weights_config.fetch(c[:product_name].to_s, 1.0).to_f
        { candidate: c, weight: [w, 0.0].max }
      end

      # Remove paused products (weight 0)
      weighted.reject! { |w| w[:weight] <= 0 }
      return nil if weighted.empty?

      total = weighted.sum { |w| w[:weight] }
      r = rand * total
      cumulative = 0.0
      weighted.each do |w|
        cumulative += w[:weight]
        return w[:candidate][:topic] if r < cumulative
      end

      weighted.last[:candidate][:topic]
    end

    # ----------------------------------------------------------------
    private

    def self.load_weights(type_id)
      all = JSON.parse(SiteSetting.digest_mix_product_weights)
      (all[type_id] || {}).transform_keys(&:to_s).transform_values(&:to_f)
    rescue
      {}
    end
  end
end
