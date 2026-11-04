module SegmentRules
  # Checks a segment definition against the allow-lists in SegmentRules.
  #
  #   validator = SegmentRules::Validator.new(definition)
  #   validator.valid?   # => false
  #   validator.errors   # => ["rule 1: field must be one of: pass_type, ..."]
  class Validator
    # The keys each rule type may have. Any other key is an error.
    RULE_KEYS = {
      "attribute" => %w[type field operator value],
      "event_count" => %w[type event difficulty operator value window_days],
      "last_event" => %w[type operator days]
    }.freeze

    attr_reader :errors

    def initialize(definition)
      @definition = definition
      @errors = []
    end

    def valid?
      @errors = []
      check_definition
      @errors.empty?
    end

    private

    def check_definition
      return error("rules must be an object") unless @definition.is_a?(Hash)

      definition = @definition.deep_stringify_keys
      unknown_keys(definition, %w[match rules], "rules")
      error(%(match must be "all" or "any")) unless MATCHES.key?(definition["match"])

      rules = definition["rules"]
      unless rules.is_a?(Array) && rules.size.between?(1, MAX_RULES)
        return error("rules must be a list of 1 to #{MAX_RULES} rules")
      end

      rules.each.with_index(1) { |rule, i| check_rule(rule, "rule #{i}") }
    end

    def check_rule(rule, at)
      return error("#{at}: must be an object") unless rule.is_a?(Hash)

      keys = RULE_KEYS[rule["type"]]
      return error("#{at}: type must be one of: #{RULE_KEYS.keys.join(', ')}") unless keys

      unknown_keys(rule, keys, at)
      send("check_#{rule['type']}", rule, at)
    end

    def check_attribute(rule, at)
      spec = ATTRIBUTES[rule["field"]]
      return error("#{at}: field must be one of: #{ATTRIBUTES.keys.join(', ')}") unless spec

      operator = rule["operator"]
      unless ATTRIBUTE_OPERATORS.include?(operator)
        return error("#{at}: operator must be one of: #{ATTRIBUTE_OPERATORS.join(', ')}")
      end

      values = operator == "in" ? rule["value"] : [ rule["value"] ]
      unless values.is_a?(Array) && !values.empty?
        return error("#{at}: value must be a non-empty list when operator is in")
      end

      unless values.all? { |value| spec[:values].include?(value) }
        error("#{at}: value for #{rule['field']} must be one of: #{spec[:values].join(', ')}")
      end
    end

    def check_event_count(rule, at)
      unless EVENT_TYPES.include?(rule["event"])
        error("#{at}: event must be one of: #{EVENT_TYPES.join(', ')}")
      end

      if rule.key?("difficulty")
        if rule["event"] != "lift_scan"
          error("#{at}: difficulty only applies to lift_scan events")
        elsif !DIFFICULTIES.include?(rule["difficulty"])
          error("#{at}: difficulty must be one of: #{DIFFICULTIES.join(', ')}")
        end
      end

      unless COUNT_OPERATORS.key?(rule["operator"])
        error("#{at}: operator must be one of: #{COUNT_OPERATORS.keys.join(', ')}")
      end

      whole_number(rule, "value", 0, MAX_COUNT, at)
      whole_number(rule, "window_days", 1, MAX_DAYS, at) if rule.key?("window_days")
    end

    def check_last_event(rule, at)
      unless LAST_EVENT_OPERATORS.include?(rule["operator"])
        error("#{at}: operator must be one of: #{LAST_EVENT_OPERATORS.join(', ')}")
      end

      whole_number(rule, "days", 1, MAX_DAYS, at)
    end

    def whole_number(rule, key, min, max, at)
      value = rule[key]
      return if value.is_a?(Integer) && value.between?(min, max)

      error("#{at}: #{key} must be a whole number from #{min} to #{max}")
    end

    def unknown_keys(hash, allowed, at)
      extra = hash.keys - allowed
      error("#{at}: unknown keys: #{extra.join(', ')}") if extra.any?
    end

    def error(message)
      @errors << message
    end
  end
end
