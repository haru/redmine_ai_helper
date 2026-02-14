# frozen_string_literal: true
require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # GeminiProvider configures RubyLLM for Google Gemini API access.
    class GeminiProvider < RedmineAiHelper::LlmClient::BaseProvider
      # Configure RubyLLM with Gemini API key.
      # @return [void]
      def configure_ruby_llm
        setting = AiHelperSetting.find_or_create
        model_profile = setting.model_profile
        raise "Model Profile not found" unless model_profile
        RubyLLM.configure do |config|
          config.gemini_api_key = model_profile.access_key
        end
      end
    end
  end
end
