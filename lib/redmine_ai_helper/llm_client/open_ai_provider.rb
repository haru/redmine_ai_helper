# frozen_string_literal: true
require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # OpenAiProvider configures RubyLLM for OpenAI API access.
    class OpenAiProvider < RedmineAiHelper::LlmClient::BaseProvider

      protected

      def ruby_llm_provider_class
        RubyLLM::Providers::OpenAI
      end

      def ruby_llm_provider_slug
        "openai"
      end

      def configure_provider_config(config)
        profile = resolved_model_profile
        config.openai_api_key = profile.access_key
        config.openai_organization_id = profile.organization_id if profile.organization_id
      end

      # Build a RubyLLM::Context with OpenAI API key and organization.
      # @return [RubyLLM::Context]
      def build_context
        profile = resolved_model_profile
        raise "Model Profile not found" unless profile
        RubyLLM.context do |config|
          config.openai_api_key = profile.access_key
          config.openai_organization_id = profile.organization_id if profile.organization_id
        end
      end
    end
  end
end
