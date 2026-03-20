# frozen_string_literal: true
require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # GeminiProvider configures RubyLLM for Google Gemini API access.
    class GeminiProvider < RedmineAiHelper::LlmClient::BaseProvider

      protected

      def ruby_llm_provider_class
        RubyLLM::Providers::Gemini
      end

      def ruby_llm_provider_slug
        "gemini"
      end

      def configure_provider_config(config)
        config.gemini_api_key = resolved_model_profile.access_key
      end

      # Build a RubyLLM::Context with Gemini API key.
      # @return [RubyLLM::Context]
      def build_context
        profile = resolved_model_profile
        raise "Model Profile not found" unless profile
        RubyLLM.context do |config|
          config.gemini_api_key = profile.access_key
        end
      end
    end
  end
end
