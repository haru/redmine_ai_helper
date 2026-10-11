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
      # default applies. When caching is disabled, behaves like the base class.
      # @param chat [RubyLLM::Chat] the chat instance to configure
      # @param instructions [String, Instructions, nil] system prompt
      # @return [void]
      def apply_instructions(chat, instructions)
        return super unless resolved_model_profile.prompt_caching_enabled

        chat.with_caching
        case instructions
        when nil
          nil
        when RedmineAiHelper::LlmClient::Instructions
          chat.with_instructions(instructions.fixed, cache_until_here: true)
          chat.with_instructions(instructions.variable, append: true) unless instructions.variable.to_s.empty?
        else
          chat.with_instructions(instructions, cache_until_here: true)
        end
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
