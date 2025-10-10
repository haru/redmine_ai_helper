# frozen_string_literal: true
require "langchain"

module RedmineAiHelper
  module Util
    # Patch module for extending Langchain functionality.
    # This module provides refinements to Langchain classes to support
    # recursive tool definition generation, particularly for MCP tools
    # that require nested object and array properties.
    module LangchainPatch
      # A patch to enable recursive calls for creating Object properties when automatically
      # generating Tool definitions in MCPTools
      refine Langchain::ToolDefinition::ParameterBuilder do
        def build_properties_from_json(json)
          properties = json["properties"] || {}
          items = json["items"]
          properties.each do |key, value|
            type = value["type"]
            case type
            when "object", "array"
              property key.to_sym, type: type, description: value["description"] do
                build_properties_from_json(value)
              end
            else
              property key.to_sym, type: type, description: value["description"]
            end
          end
          if items
            @parent_type = "array"
            type = items["type"]
            description = items["description"]
            case type
            when "object", "array"
              item type: type, description: description do
                @parent_type = type
                build_properties_from_json(items)
              end
            else
              item type: type
            end
          end
        end
      end
    end
  end
end
