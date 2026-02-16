# frozen_string_literal: true
require "ruby_llm"
require "redmine_ai_helper/logger"

module RedmineAiHelper
  # @!visibility private
  ROUTE_HELPERS = Rails.application.routes.url_helpers unless const_defined?(:ROUTE_HELPERS)

  # Base class for all tools.
  # Provides a DSL (define_function / property / item) that internally generates
  # RubyLLM::Tool subclasses.
  class BaseTools
    include RedmineAiHelper::Logger
    include ROUTE_HELPERS

    class << self
      # Returns the array of generated RubyLLM::Tool subclasses for this tools class.
      # @return [Array<Class>] array of RubyLLM::Tool subclasses
      def tool_classes
        @tool_classes ||= []
      end

      # Define a function using a DSL that internally generates a RubyLLM::Tool subclass.
      # @param name [Symbol] function name (must match an instance method on this class)
      # @param description [String] human-readable description of the function
      # @param block [Proc] block containing property/item definitions
      def define_function(name, description:, &block)
        tools_class = self
        func_name = name.to_sym

        # Build parameter schema from the DSL block
        param_builder = ParameterBuilder.new
        param_builder.instance_eval(&block) if block_given?

        # Build JSON schema from collected parameters
        json_schema = param_builder.to_json_schema

        # Generate a RubyLLM::Tool subclass
        tool_class = Class.new(RubyLLM::Tool) do
          description description

          # Set the JSON schema directly via params
          params json_schema if json_schema

          # execute delegates to the actual method on a tools instance
          define_method :execute do |**kwargs|
            instance = tools_class.new
            instance.send(func_name, **kwargs)
          end
        end

        # Provide a meaningful class name for debugging and tool name generation
        tool_class_name = "#{tools_class.name || "AnonymousTools"}::#{func_name.to_s.camelize}"
        tool_class.define_singleton_method(:name) { tool_class_name }
        tool_class.define_singleton_method(:to_s) { tool_class_name }

        tool_classes << tool_class

        # Store function metadata for backward compatibility (function_schemas)
        function_registry[func_name] = {
          description: description,
          param_builder: param_builder,
          tool_class: tool_class,
        }
      end

      # Backward compatibility: provides function_schemas.to_openai_format
      # used by base_agent.rb and mcp_tools.rb
      # @return [FunctionSchemas] wrapper with to_openai_format method
      def function_schemas
        FunctionSchemas.new(self)
      end

      # Registry of defined functions and their metadata
      # @return [Hash] function name => metadata hash
      def function_registry
        @function_registry ||= {}
      end
    end

    # ParameterBuilder: property/item DSL for building JSON schema definitions.
    class ParameterBuilder
      attr_reader :params

      def initialize
        @params = []
      end

      # Define a property parameter
      # @param name [Symbol] parameter name
      # @param type [String] parameter type ("string", "integer", "boolean", "number", "object", "array")
      # @param description [String] parameter description
      # @param required [Boolean] whether the parameter is required
      # @param enum [Array, nil] allowed values for the parameter
      # @param block [Proc] block for nested properties (object/array types)
      def property(name, type:, description: "", required: false, enum: nil, &block)
        param = { name: name.to_sym, type: type, description: description, required: required }
        param[:enum] = enum if enum

        if block_given? && (type == "object" || type == "array")
          child_builder = ParameterBuilder.new
          child_builder.instance_eval(&block)
          if type == "object"
            param[:children] = child_builder.params
          elsif type == "array"
            param[:items] = child_builder.items_definition
            # Also store named item parts for arrays of objects with named sub-items
            param[:items_parts] = child_builder.items_parts if child_builder.items_parts&.any?
          end
        end

        @params << param
      end

      # Define an array item
      # @param name_or_type [Symbol, nil] item name (optional, used in some DSL patterns)
      # @param type [String] item type
      # @param description [String] item description
      # @param required [Boolean] whether the item is required
      # @param enum [Array, nil] allowed values
      # @param block [Proc] block for nested properties
      def item(name_or_type = nil, type: nil, description: "", required: false, enum: nil, &block)
        # Handle both `item type: "string"` and `item :name, type: "string"` patterns
        if name_or_type.is_a?(Symbol) && type
          # Named item pattern: `item :key, type: "string", ...`
          item_def = { name: name_or_type, type: type, description: description, required: required }
          item_def[:enum] = enum if enum
          if block_given? && (type == "object" || type == "array")
            child_builder = ParameterBuilder.new
            child_builder.instance_eval(&block)
            item_def[:children] = child_builder.params if child_builder.params.any?
            item_def[:items] = child_builder.items_definition if type == "array"
            item_def[:items_parts] = child_builder.items_parts if child_builder.items_parts&.any?
          end
          @items_parts ||= []
          @items_parts << item_def
        else
          # Unnamed item pattern: `item type: "string"` or `item type: "object" do ... end`
          actual_type = type || name_or_type.to_s
          @items_definition = { type: actual_type, description: description }
          @items_definition[:enum] = enum if enum
          if block_given? && (actual_type == "object" || actual_type == "array")
            child_builder = ParameterBuilder.new
            child_builder.instance_eval(&block)
            @items_definition[:children] = child_builder.params if child_builder.params.any?
            @items_definition[:items_parts] = child_builder.items_parts if child_builder.items_parts&.any?
          end
        end
      end

      # Returns the items definition for array types
      def items_definition
        @items_definition
      end

      # Returns named item parts (for object-like array items with named sub-items)
      def items_parts
        @items_parts
      end

      # Build parameter definitions from a JSON schema hash
      # @param json [Hash] JSON schema
      def build_properties_from_json(json)
        properties = json["properties"] || {}
        items = json["items"]
        required_fields = json["required"] || []

        properties.each do |key, value|
          type = value["type"]
          case type
          when "object", "array"
            property key.to_sym, type: type, description: value["description"] || "", required: required_fields.include?(key) do
              build_properties_from_json(value)
            end
          else
            prop_opts = { type: type, description: value["description"] || "", required: required_fields.include?(key) }
            prop_opts[:enum] = value["enum"] if value["enum"]
            property key.to_sym, **prop_opts
          end
        end

        if items
          type = items["type"]
          description = items["description"] || ""
          case type
          when "object", "array"
            item type: type, description: description do
              build_properties_from_json(items)
            end
          else
            item type: type, description: description
          end
        end
      end

      # Convert collected parameter definitions to JSON schema
      # @return [Hash, nil] JSON schema hash or nil if no parameters
      def to_json_schema
        return nil if @params.empty?

        properties = {}
        required = []

        @params.each do |p|
          prop_schema = build_property_schema(p)
          properties[p[:name].to_s] = prop_schema
          required << p[:name].to_s if p[:required]
        end

        {
          type: "object",
          properties: properties,
          required: required,
        }
      end

      private

      # Build JSON schema for a single property
      def build_property_schema(param)
        schema = { type: param[:type] }
        schema[:description] = param[:description] if param[:description] && !param[:description].empty?
        schema[:enum] = param[:enum] if param[:enum]

        case param[:type]
        when "object"
          if param[:children] && param[:children].any?
            child_properties = {}
            child_required = []
            param[:children].each do |child|
              child_properties[child[:name].to_s] = build_property_schema(child)
              child_required << child[:name].to_s if child[:required]
            end
            schema[:properties] = child_properties
            schema[:required] = child_required unless child_required.empty?
          end
        when "array"
          if param[:items]
            schema[:items] = build_items_schema(param[:items])
          elsif param[:items_parts] && param[:items_parts].any?
            # Named item parts pattern (item :key, type: "string")
            schema[:items] = build_items_from_parts(param[:items_parts])
          end
        end

        schema
      end

      # Build JSON schema for array items
      def build_items_schema(items_def)
        schema = { type: items_def[:type] }
        schema[:description] = items_def[:description] if items_def[:description] && !items_def[:description].empty?
        schema[:enum] = items_def[:enum] if items_def[:enum]

        if items_def[:type] == "object"
          if items_def[:children] && items_def[:children].any?
            child_properties = {}
            child_required = []
            items_def[:children].each do |child|
              child_properties[child[:name].to_s] = build_property_schema(child)
              child_required << child[:name].to_s if child[:required]
            end
            schema[:properties] = child_properties
            schema[:required] = child_required unless child_required.empty?
          elsif items_def[:items_parts] && items_def[:items_parts].any?
            schema = build_items_from_parts(items_def[:items_parts])
          end
        end

        schema
      end

      # Build JSON schema for named item parts
      def build_items_from_parts(parts)
        child_properties = {}
        child_required = []
        parts.each do |part|
          child_properties[part[:name].to_s] = build_property_schema(part)
          child_required << part[:name].to_s if part[:required]
        end
        schema = { type: "object" }
        schema[:properties] = child_properties
        schema[:required] = child_required unless child_required.empty?
        schema
      end
    end

    # Backward compatibility wrapper for function_schemas.to_openai_format
    # Used by base_agent.rb and mcp_tools.rb during the transition period.
    class FunctionSchemas
      def initialize(tools_class)
        @tools_class = tools_class
      end

      # Generate OpenAI function calling format from the registered functions
      # @return [Array<Hash>] array of function definitions in OpenAI format
      def to_openai_format
        @tools_class.function_registry.map do |func_name, metadata|
          schema = metadata[:param_builder].to_json_schema || { type: "object", properties: {} }
          func_full_name = generate_function_name(func_name)
          {
            type: "function",
            function: {
              name: func_full_name,
              description: metadata[:description],
              parameters: deep_symbolize_keys(schema),
            },
          }
        end
      end

      private

      # Generate function name from class name and method name
      # e.g., "redmine_ai_helper_tools_issue_tools__read_issues"
      def generate_function_name(func_name)
        class_name = @tools_class.name || "anonymous_tools"
        prefix = class_name.underscore.gsub("/", "_")
        "#{prefix}__#{func_name}"
      end

      # Recursively convert hash keys to symbols
      def deep_symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)
        hash.each_with_object({}) do |(key, value), result|
          sym_key = key.to_sym
          result[sym_key] = case value
                            when Hash then deep_symbolize_keys(value)
                            when Array then value.map { |v| v.is_a?(Hash) ? deep_symbolize_keys(v) : v }
                            else value
                            end
        end
      end
    end

    # Check if the specified project is accessible
    # @param project [Project] The project
    # @return [Boolean] true if accessible, false otherwise
    def accessible_project?(project)
      return false unless project.visible?
      return false unless project.module_enabled?(:ai_helper)
      User.current.allowed_to?({ controller: :ai_helper, action: :chat_form }, project)
    end
  end
end
