# frozen_string_literal: true

require "mcp"
require "json"

module RedmineAiHelper
  module Mcp
    # Adapts a RubyLLM::Tool subclass into an MCP::Tool subclass.
    #
    # Extracts the tool name (last function name segment), description, and
    # JSON Schema from the source RubyLLM tool, then creates an MCP::Tool
    # subclass whose +call+ method delegates execution to the RubyLLM tool
    # and wraps the result in MCP content format.
    #
    # @example
    #   mcp_tool = ToolAdapter.adapt(IssueSearchTools.tool_classes.first)
    #   server = MCP::Server.new(tools: [mcp_tool])
    class ToolAdapter
      class << self
        # Converts a RubyLLM::Tool subclass into an MCP::Tool subclass.
        #
        # @param ruby_tool_class [Class] a subclass of RubyLLM::Tool
        # @return [Class] a subclass of MCP::Tool
        def adapt(ruby_tool_class)
          instance = ruby_tool_class.new
          tool_name = extract_tool_name(instance)
          tool_description = ruby_tool_class.description.to_s
          tool_schema = sanitize_schema(instance.params_schema || {})

          MCP::Tool.define(
            name: tool_name,
            description: tool_description,
            input_schema: tool_schema
          ) do |**arguments|
            tool_args = arguments.reject { |k, _| k == :server_context }
            ToolAdapter.call_ruby_tool(ruby_tool_class, tool_args)
          end
        end

        # Executes the RubyLLM tool and returns an MCP result hash.
        # Tool-level errors are surfaced to the MCP client via +isError: true+
        # rather than raising, as required by the MCP +tools/call+ contract.
        #
        # @param ruby_tool_class [Class] RubyLLM::Tool subclass
        # @param arguments [Hash] symbol-keyed arguments from MCP
        # @return [Hash] MCP result with :content and :isError
        def call_ruby_tool(ruby_tool_class, arguments)
          result = ruby_tool_class.new.call(arguments)

          if result.is_a?(Hash) && result[:error]
            { content: [{ type: "text", text: result[:error].to_s }], isError: true }
          else
            { content: [{ type: "text", text: JSON.generate(result) }], isError: false }
          end
        rescue => e
          { content: [{ type: "text", text: e.message }], isError: true }
        end

        private

        # Extracts the short function name from a tool instance's derived name.
        # The RubyLLM name method converts the full class path to a
        # double-hyphen-separated snake_case string; we take the last segment.
        #
        # @param instance [RubyLLM::Tool] instantiated tool
        # @return [String] short function name (e.g. "search_issues")
        def extract_tool_name(instance)
          instance.name.to_s.split("--").last
        end

        # Removes empty +required+ arrays from a JSON Schema hash to ensure
        # compliance with JSON Schema draft-4 (requires >= 1 item in required).
        #
        # @param schema [Hash] raw JSON Schema hash (string keys)
        # @return [Hash] sanitized schema
        def sanitize_schema(schema)
          return schema unless schema.is_a?(Hash)

          result = schema.dup
          required = result["required"] || result[:required]
          if required.is_a?(Array) && required.empty?
            result.delete("required")
            result.delete(:required)
          end
          result
        end
      end
    end

    # @deprecated Use {ToolAdapter} directly.
    MCPToolAdapter = ToolAdapter
  end
end
