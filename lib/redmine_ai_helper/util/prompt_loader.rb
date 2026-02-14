# frozen_string_literal: true

require_relative "prompt_template"

module RedmineAiHelper
  module Util
    # A class that loads prompt templates from YAML files.
    # The templates are stored in the assets/prompt_templates directory.
    class PromptLoader
      class << self
        # Loads a prompt template from a YAML file.
        # @param name [String] The name of the template file (without extension).
        # @return [PromptTemplate] The loaded prompt template.
        def load_template(name)
          tepmlate_base_dir = File.dirname(__FILE__) + "/../../../assets/prompt_templates"
          locale_string = I18n.locale.to_s
          template_file = "#{tepmlate_base_dir}/#{name}_#{locale_string}.yml"
          # Check if the locale-specific template file exists
          unless File.exist?(template_file)
            template_file = "#{tepmlate_base_dir}/#{name}.yml"
          end
          PromptTemplate.load_from_path(template_file)
        end
      end
    end
  end
end
