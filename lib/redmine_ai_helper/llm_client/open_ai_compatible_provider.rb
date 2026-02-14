# frozen_string_literal: true
require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # OpenAiCompatibleProvider configures RubyLLM for OpenAI-compatible LLM endpoints.
    class OpenAiCompatibleProvider < RedmineAiHelper::LlmClient::BaseProvider
      # Configure RubyLLM with custom API base URL and key.
      # @return [void]
      def configure_ruby_llm
        setting = AiHelperSetting.find_or_create
        model_profile = setting.model_profile
        raise "Model Profile not found" unless model_profile
        raise "Base URI not found" unless model_profile.base_uri
        RubyLLM.configure do |config|
          config.openai_api_key = model_profile.access_key
          config.openai_api_base = model_profile.base_uri
        end
      end

      # Create a RubyLLM::Chat instance for OpenAI-compatible endpoints.
      # Overrides base class to use provider: :openai and assume_model_exists: true.
      # @param instructions [String, nil] system prompt
      # @param tools [Array<Class>] tool classes to attach
      # @return [RubyLLM::Chat]
      def create_chat(instructions: nil, tools: [])
        configure_ruby_llm
        chat = RubyLLM.chat(
          model: model_name,
          provider: :openai,
          assume_model_exists: true,
        )
        chat.with_instructions(instructions) if instructions
        chat.with_tools(*tools) unless tools.empty?
        chat.with_temperature(temperature) if temperature
        chat
      end
    end
  end
end
