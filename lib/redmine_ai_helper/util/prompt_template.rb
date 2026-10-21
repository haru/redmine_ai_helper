# frozen_string_literal: true

require "yaml"
require_relative "../logger"

module RedmineAiHelper
  module Util
    # A lightweight prompt template class.
    # Loads YAML template files and substitutes {variable_name} placeholders.
    # #format requires the given variable names to equal the declared
    # input_variables exactly (see docs/adr/063-prompt-template-strict-input-variables.md).
    class PromptTemplate
      include RedmineAiHelper::Logger

      # A declared variable must be usable as a {name} placeholder.
      VARIABLE_NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/

      attr_reader :template, :input_variables, :path

      # @param template [String] The template string with {variable_name} placeholders
      # @param input_variables [Array<String, Symbol>] List of expected variable names;
      #   each must be a valid placeholder name and appear only once
      # @param path [String, nil] Path of the YAML file the template was loaded from, if any
      # @raise [ArgumentError] If template is not a String, path is neither a String nor nil,
      #   or input_variables is not a duplicate-free Array of valid Strings or Symbols
      def initialize(template:, input_variables: [], path: nil)
        raise ArgumentError, "template must be a String, got #{template.class}" unless template.is_a?(String)
        raise ArgumentError, "path must be a String or nil, got #{path.class}" unless path.nil? || path.is_a?(String)
        unless input_variables.is_a?(Array)
          raise ArgumentError, "input_variables must be an Array, got #{input_variables.class}"
        end

        @template = template.dup.freeze
        @input_variables = normalize_variable_names(input_variables).freeze
        @path = path
      end

      # Load a prompt template from a YAML file.
      # @param file_path [String] Path to the YAML file
      # @return [PromptTemplate] The loaded template
      # @raise [ArgumentError] If the file does not hold a mapping with a String template and
      #   a valid input_variables list. The message does not contain the file path;
      #   the path goes to the error log.
      def self.load_from_path(file_path)
        yaml = YAML.safe_load(File.read(file_path))
        raise ArgumentError, "YAML root must be a mapping, got #{yaml.class}" unless yaml.is_a?(Hash)

        new(
          template: yaml["template"],
          input_variables: yaml.fetch("input_variables", []),
          path: file_path
        )
      rescue ArgumentError => e
        ai_helper_logger.error("Invalid prompt template (#{file_path}): #{e.message}")
        raise
      end

      # Substitute {variable_name} placeholders with the provided values.
      # The given variable names must equal the declared input_variables.
      # Uses block form of gsub to avoid Ruby backreference issues with
      # backslash sequences in replacement strings.
      # @param kwargs [Hash] Variable name => value pairs
      # @return [String] The formatted string
      # @raise [ArgumentError] If a declared variable is missing, an undeclared one is given,
      #   or a String and a Symbol key name the same variable.
      #   The message names the variables only; the template file path goes to the error log.
      def format(**kwargs)
        given = kwargs.keys.map(&:to_s)
        missing = @input_variables - given
        unknown = given - @input_variables
        duplicated = given.tally.select { |_name, count| count > 1 }.keys
        unless missing.empty? && unknown.empty? && duplicated.empty?
          clauses = []
          clauses << "Missing prompt variables: #{missing.join(", ")}" unless missing.empty?
          clauses << "unknown prompt variables: #{unknown.join(", ")}" unless unknown.empty?
          clauses << "Duplicate prompt variables: #{duplicated.join(", ")}" unless duplicated.empty?
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

      private

      # @param names [Array] The declared variable names
      # @return [Array<String>] The names as Strings
      # @raise [ArgumentError] If an element is not a String or Symbol, is not a valid
      #   placeholder name, or appears more than once
      def normalize_variable_names(names)
        normalized = names.map do |name|
          case name
          when String, Symbol
            raise ArgumentError, "input_variables contains an invalid name: #{name.to_s.inspect}" unless VARIABLE_NAME.match?(name.to_s)

            name.to_s
          else
            raise ArgumentError, "input_variables elements must be String or Symbol, got #{name.class}"
          end
        end
        duplicated = normalized.tally.select { |_name, count| count > 1 }.keys
        raise ArgumentError, "input_variables must not contain duplicates: #{duplicated.join(", ")}" unless duplicated.empty?

        normalized
      end
    end
  end
end
