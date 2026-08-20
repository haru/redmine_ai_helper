require_relative "../logger"

module RedmineAiHelper
  module Util
    # Utility class for loading configuration files for the AI Helper plugin.
    # Handles loading and parsing of YAML configuration files.
    class ConfigFile
      include RedmineAiHelper::Logger

      # Timeout, in seconds, used for the completion LLM request when the
      # configuration file does not set one, or sets one we cannot accept.
      AUTOCOMPLETION_DEFAULT_TIMEOUT = 30

      # Accepted range, in seconds, for the autocompletion timeout.
      AUTOCOMPLETION_TIMEOUT_RANGE = (1..600).freeze

      # Accepted format for the inline suggestion color. The value is embedded in
      # a JavaScript string literal by the overlay templates, so only #RGB and
      # #RRGGBB are allowed.
      SUGGESTION_COLOR_FORMAT = /\A#\h{3}(\h{3})?\z/

      # Every key the `autocompletion` section understands. Anything else is
      # reported so that a typo, or a key dropped in a past release, is visible
      # in the log instead of being silently ignored.
      AUTOCOMPLETION_KNOWN_KEYS = %i[timeout debounce_delay min_length wiki_min_length suggestion_color].freeze

      # Load the configuration file and return its contents as a hash.
      # @return [Hash] The configuration hash with symbolized keys, or an empty hash if the file doesn't exist.
      def self.load_config
        unless File.exist?(config_file_path)
          return {}
        end

        yaml = YAML.load_file(config_file_path)
        yaml.deep_symbolize_keys
      end

      # Get the path to the configuration file.
      # @return [Pathname] The path to the configuration file (config/ai_helper/config.yml).
      def self.config_file_path
        Rails.root.join("config/ai_helper/config.yml")
      end

      # Read and validate the `autocompletion` section of the configuration file.
      #
      # This method never raises: a missing file, a broken YAML document or an
      # invalid value all yield defaults so that the edit screens keep rendering.
      # Every rejected value is reported once, through the plugin logger when it
      # is usable and through Rails.logger otherwise (see {warn_config}).
      #
      # @return [Hash] Validated settings:
      #   * +:timeout+ [Integer] always within AUTOCOMPLETION_TIMEOUT_RANGE
      #   * +:debounce_delay+ [Numeric, nil] nil means "use the view default"
      #   * +:min_length+ [Integer, nil] nil means "use the view default"
      #   * +:wiki_min_length+ [Integer, nil] nil means "fall back to :min_length"
      #   * +:suggestion_color+ [String, nil] nil means "use the view default";
      #     a non-nil value always matches SUGGESTION_COLOR_FORMAT
      def self.autocompletion_settings
        section = autocompletion_section
        warn_unknown_keys(section)
        {
          timeout: validated_timeout(section[:timeout]),
          debounce_delay: validated_debounce_delay(section[:debounce_delay]),
          min_length: validated_min_length(:min_length, section[:min_length]),
          wiki_min_length: validated_min_length(:wiki_min_length, section[:wiki_min_length]),
          suggestion_color: validated_suggestion_color(section[:suggestion_color])
        }
      end

      # Read the raw `autocompletion` section, tolerating an unreadable file.
      # @return [Hash] The section with symbolized keys, or an empty hash.
      def self.autocompletion_section
        section = load_config[:autocompletion]
        return {} if section.nil?
        return section if section.is_a?(Hash)

        warn_invalid_setting(:autocompletion, section, "not a mapping")
        {}
      rescue StandardError => e
        warn_config("Failed to read #{config_file_path} (#{e.class}: #{e.message}). Using default autocompletion settings.")
        {}
      end
      private_class_method :autocompletion_section

      # Report keys the `autocompletion` section does not understand.
      # @param section [Hash] The raw section read from the configuration file.
      # @return [void]
      def self.warn_unknown_keys(section)
        (section.keys - AUTOCOMPLETION_KNOWN_KEYS).each do |key|
          warn_config("Ignoring unknown autocompletion setting #{key} in #{config_file_path}.")
        end
      end
      private_class_method :warn_unknown_keys

      # Validate the LLM request timeout, in seconds.
      # @param value [Object] The raw value read from the configuration file.
      # @return [Integer] A timeout within AUTOCOMPLETION_TIMEOUT_RANGE.
      def self.validated_timeout(value)
        return AUTOCOMPLETION_DEFAULT_TIMEOUT if value.nil?

        number = coerce_number(value)
        if number.nil?
          warn_invalid_setting(:timeout, value, "not a number")
          return AUTOCOMPLETION_DEFAULT_TIMEOUT
        end

        seconds = number.to_i
        unless AUTOCOMPLETION_TIMEOUT_RANGE.cover?(seconds)
          warn_invalid_setting(:timeout, value, "out of range #{AUTOCOMPLETION_TIMEOUT_RANGE}")
          return AUTOCOMPLETION_DEFAULT_TIMEOUT
        end

        seconds
      end
      private_class_method :validated_timeout

      # Validate the debounce delay, in milliseconds.
      # @param value [Object] The raw value read from the configuration file.
      # @return [Numeric, nil] A positive number, or nil to use the view default.
      def self.validated_debounce_delay(value)
        return nil if value.nil?

        number = coerce_number(value)
        if number.nil? || number <= 0
          warn_invalid_setting(:debounce_delay, value, "not a positive number")
          return nil
        end

        number
      end
      private_class_method :validated_debounce_delay

      # Validate the minimum body length that triggers a completion.
      # @param key [Symbol] The configuration key being validated, for the log line.
      # @param value [Object] The raw value read from the configuration file.
      # @return [Integer, nil] A non-negative integer, or nil to use the view default.
      def self.validated_min_length(key, value)
        return nil if value.nil?

        number = coerce_number(value)
        if number.nil? || number.negative? || number != number.to_i
          warn_invalid_setting(key, value, "not a non-negative integer")
          return nil
        end

        number.to_i
      end
      private_class_method :validated_min_length

      # Validate the inline suggestion color.
      # @param value [Object] The raw value read from the configuration file.
      # @return [String, nil] A #RGB or #RRGGBB color, or nil to use the view default.
      def self.validated_suggestion_color(value)
        return nil if value.nil?

        unless value.is_a?(String) && value.match?(SUGGESTION_COLOR_FORMAT)
          warn_invalid_setting(:suggestion_color, value, "not a #RGB or #RRGGBB color")
          return nil
        end

        value
      end
      private_class_method :validated_suggestion_color

      # Convert a configuration value to a number, accepting numeric strings.
      # Integral results are returned as Integer so that views render them plainly.
      # @param value [Object] The raw value read from the configuration file.
      # @return [Numeric, nil] The number, or nil when the value is not numeric.
      def self.coerce_number(value)
        number = case value
        when Numeric then value
        when String then Float(value, exception: false)
        end
        return nil if number.nil?

        number == number.to_i ? number.to_i : number
      end
      private_class_method :coerce_number

      # Report a rejected configuration value through the plugin logger.
      # @param key [Symbol] The configuration key that was rejected.
      # @param value [Object] The value that failed validation.
      # @param reason [String] Why the value was rejected.
      # @return [void]
      def self.warn_invalid_setting(key, value, reason)
        warn_config("Ignoring autocompletion setting #{key}=#{value.inspect} in #{config_file_path}: #{reason}. Using the default value.")
      end
      private_class_method :warn_invalid_setting

      # Write a configuration warning without ever raising.
      #
      # CustomLogger parses this same configuration file when it is first
      # instantiated, so asking for the plugin logger can fail for exactly the
      # reason we are trying to report. Falling back to Rails.logger keeps that
      # failure from escaping and breaking the caller.
      # @param message [String] The warning to record.
      # @return [void]
      def self.warn_config(message)
        ai_helper_logger.warn message
      rescue StandardError
        Rails.logger&.warn message
      end
      private_class_method :warn_config
    end
  end
end
