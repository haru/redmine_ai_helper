# frozen_string_literal: true
require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # AnthropicProvider configures RubyLLM for Anthropic API access.
    class AnthropicProvider < RedmineAiHelper::LlmClient::BaseProvider

      protected

      def ruby_llm_provider_class
        RubyLLM::Providers::Anthropic
      end

      def ruby_llm_provider_slug
        "anthropic"
      end

      def configure_provider_config(config)
        config.anthropic_api_key = resolved_model_profile.access_key
      end

      # Build a RubyLLM::Context with Anthropic API key.
      # @return [RubyLLM::Context]
      def build_context
        profile = resolved_model_profile
        raise "Model Profile not found" unless profile
        RubyLLM.context do |config|
          config.anthropic_api_key = profile.access_key
        end
      end
    end
  end
end
