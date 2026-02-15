# frozen_string_literal: true

require "yaml"

module RedmineAiHelper
  module Util
    # A lightweight prompt template class.
    # Loads YAML template files and substitutes {variable_name} placeholders.
    class PromptTemplate
      attr_reader :template, :input_variables

      # @param template [String] The template string with {variable_name} placeholders
      # @param input_variables [Array<String>] List of expected variable names
      def initialize(template:, input_variables: [])
        @template = template
        @input_variables = input_variables
      end

      # Load a prompt template from a YAML file.
      # @param file_path [String] Path to the YAML file
      # @return [PromptTemplate] The loaded template
      def self.load_from_path(file_path)
        yaml = YAML.safe_load(File.read(file_path))
        new(
          template: yaml["template"],
          input_variables: yaml["input_variables"] || [],
        )
      end

      # Substitute {variable_name} placeholders with the provided values.
      # Uses block form of gsub to avoid Ruby backreference issues with
      # backslash sequences in replacement strings.
      # @param kwargs [Hash] Variable name => value pairs
      # @return [String] The formatted string
      def format(**kwargs)
        result = @template.dup
        kwargs.each do |key, value|
          result = result.gsub("{#{key}}") { value.to_s }
        end
        result
      end
    end
  end
end
