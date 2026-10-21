# frozen_string_literal: true

require "yaml"

module RedmineAiHelper
  module Util
    # A lightweight prompt template class.
    # Loads YAML template files and substitutes {variable_name} placeholders.
    class PromptTemplate
      include RedmineAiHelper::Logger

      attr_reader :template, :input_variables, :path

      # @param template [String] The template string with {variable_name} placeholders
      # @param input_variables [Array<String, Symbol>] List of expected variable names
      # @param path [String, nil] Path of the YAML file the template was loaded from, if any
      # @raise [ArgumentError] If input_variables is not an Array of Strings or Symbols
      def initialize(template:, input_variables: [], path: nil)
        unless input_variables.is_a?(Array)
          raise ArgumentError, "input_variables must be an Array, got #{input_variables.class}"
        end

        @template = template
        @input_variables = input_variables.map do |name|
          case name
          when String, Symbol
            name.to_s
          else
            raise ArgumentError, "input_variables elements must be String or Symbol, got #{name.class}"
          end
        end
        @path = path
      end

      # Load a prompt template from a YAML file.
      # @param file_path [String] Path to the YAML file
      # @return [PromptTemplate] The loaded template
      def self.load_from_path(file_path)
        yaml = YAML.safe_load(File.read(file_path))
        new(
          template: yaml["template"],
          input_variables: yaml["input_variables"] || [],
          path: file_path
        )
      end

      # Substitute {variable_name} placeholders with the provided values.
      # The given variable names must equal the declared input_variables.
      # Uses block form of gsub to avoid Ruby backreference issues with
      # backslash sequences in replacement strings.
      # @param kwargs [Hash] Variable name => value pairs
      # @return [String] The formatted string
      # @raise [ArgumentError] If a declared variable is missing or an undeclared one is given.
      #   The message names the variables only; the template file path goes to the error log.
      def format(**kwargs)
        given = kwargs.keys.map(&:to_s)
        missing = @input_variables - given
        unknown = given - @input_variables
        unless missing.empty? && unknown.empty?
          clauses = []
          clauses << "Missing prompt variables: #{missing.join(", ")}" unless missing.empty?
          clauses << "unknown prompt variables: #{unknown.join(", ")}" unless unknown.empty?
          message = clauses.join("; ")
          location = @path ? " (#{@path})" : ""
          ai_helper_logger.error("Prompt template variable mismatch#{location}: #{message}")
          raise ArgumentError, message
        end

        result = @template.dup
        kwargs.each do |key, value|
          result = result.gsub("{#{key}}") { value.to_s }
        end
        result
      end
    end
  end
end
