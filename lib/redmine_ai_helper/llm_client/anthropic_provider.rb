# frozen_string_literal: true

require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # AnthropicProvider configures RubyLLM for Anthropic API access.
    class AnthropicProvider < RedmineAiHelper::LlmClient::BaseProvider
      protected

      # Applies the system prompt with Anthropic prompt caching.
      # When the profile has prompt caching enabled, the request gets an
      # automatic cache breakpoint (covering tools and the conversation so far)
      # and the fixed part of the system prompt is cached as its own system
      # block, so it is reused across different questions. The variable part
      # follows without a cache marker. No TTL is given, so the provider
      # default applies. A plain String is cached as a whole. When caching is
      # disabled, behaves like the base class.
      # @param chat [RubyLLM::Chat] the chat instance to configure
      # @param instructions [String, Instructions, nil] system prompt
      # @return [void]
      # @raise [ArgumentError] when +instructions+ is of any other type
      def apply_instructions(chat, instructions)
        profile = resolved_model_profile
        raise "Model Profile not found" unless profile
        return super unless profile.prompt_caching_active?

        instructions = Instructions.coerce(instructions)
        chat.with_caching
        return unless instructions

        chat.with_instructions(instructions.fixed, cache_until_here: true)
        chat.with_instructions(instructions.variable, append: true) if instructions.variable?
      end

      # Anthropic rejects object schemas that do not set
      # `additionalProperties: false` explicitly, so every object node in the
      # schema gets it unless the schema already specifies a value.
      # @param schema [Hash] payload (`{ name:, schema:, strict: }`)
      # @return [Hash] payload with a closed-object schema
      def prepare_schema(schema)
        schema.merge(schema: close_objects(schema[:schema]))
      end

      def ruby_llm_provider_class
        RubyLLM::Providers::Anthropic
      end

      def ruby_llm_provider_slug
        "anthropic"
      end

      def configure_provider_config(config)
        config.anthropic_api_key = resolved_model_profile.access_key
        configure_http_proxy(config)
      end

      # Anthropic's API has no `safety_identifier` field, so the user ID is not sent.
      def supports_user_identifier?
        false
      end

      # Recursively add `additionalProperties: false` to object nodes.
      # @param node [Object] a schema node (Hash, Array or scalar)
      # @return [Object] the node with objects closed
      def close_objects(node)
        case node
        when Hash
          closed = node.transform_values { |v| close_objects(v) }
          object = [ node["type"], node[:type] ].include?("object")
          has_key = closed.key?("additionalProperties") || closed.key?(:additionalProperties)
          closed["additionalProperties"] = false if object && !has_key
          closed
        when Array
          node.map { |v| close_objects(v) }
        else
          node
        end
      end

      # Build a RubyLLM::Context with Anthropic API key.
      # @return [RubyLLM::Context]
      def build_context
        profile = resolved_model_profile
        raise "Model Profile not found" unless profile
        RubyLLM.context do |config|
          config.anthropic_api_key = profile.access_key
          configure_http_proxy(config)
        end
      end
    end
  end
end
