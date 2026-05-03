# frozen_string_literal: true

module DigestMix
  module EmailTypePicker
    def self.pick(user)
      split = parse_split(SiteSetting.digest_mix_email_type_split)

      if CooldownChecker.push_in_cooldown?(user)
        split.delete("push")
      end

      if CooldownChecker.auto_campaign_in_cooldown?(user)
        split.delete("auto_campaign")
      end

      split = normalize(split)
      return "regular" if split.empty?

      weighted_random(split)
    end

    # ----------------------------------------------------------------
    private

    def self.parse_split(json)
      JSON.parse(json).transform_keys(&:to_s).transform_values(&:to_f)
    rescue
      { "regular" => 100.0 }
    end

    def self.normalize(split)
      total = split.values.sum.to_f
      return split if total.zero?
      split.transform_values { |v| v / total * 100.0 }
    end

    def self.weighted_random(split)
      r = rand * split.values.sum
      cumulative = 0.0
      split.each do |type, weight|
        cumulative += weight
        return type if r < cumulative
      end
      split.keys.last
    end
  end
end
