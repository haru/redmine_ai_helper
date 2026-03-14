# frozen_string_literal: true
require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # OpenAiProvider configures RubyLLM for OpenAI API access.
    class OpenAiProvider < RedmineAiHelper::LlmClient::BaseProvider

      protected

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
