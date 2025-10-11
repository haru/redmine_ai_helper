module RedmineAiHelper
  module Util
    # Utility class for loading configuration files for the AI Helper plugin.
    # Handles loading and parsing of YAML configuration files.
    class ConfigFile
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
        Rails.root.join("config", "ai_helper", "config.yml")
      end
    end
  end
end
