# frozen_string_literal: true
require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # OpenAiProvider configures RubyLLM for OpenAI API access.
    class OpenAiProvider < RedmineAiHelper::LlmClient::BaseProvider
      # Configure RubyLLM with OpenAI API key and organization.
      # @return [void]
      def configure_ruby_llm
        setting = AiHelperSetting.find_or_create
        model_profile = setting.model_profile
        raise "Model Profile not found" unless model_profile
        RubyLLM.configure do |config|
          config.openai_api_key = model_profile.access_key
          config.openai_organization_id = model_profile.organization_id if model_profile.organization_id
        end
      end
    end
  end
end
