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

      # Legacy: Generate a Langchain LLM client for backward compatibility.
      # Will be removed after full migration to ruby_llm.
      # @return [RedmineAiHelper::LangfuseUtil::Gemini] client
      def generate_client
        setting = AiHelperSetting.find_or_create
        model_profile = setting.model_profile
        raise "Model Profile not found" unless model_profile
        default_options = {
          chat_model: model_profile.llm_model,
          temperature: model_profile.temperature,
        }
        default_options[:max_tokens] = setting.max_tokens if setting.max_tokens
        client = RedmineAiHelper::LangfuseUtil::Gemini.new(
          api_key: model_profile.access_key,
          default_options: default_options,
        )
        raise "Gemini LLM Create Error" unless client
        client
      end

      # Legacy: Generate a parameter for chat completion request.
      def create_chat_param(system_prompt, messages)
        new_messages = messages.map do |message|
          role = message[:role] == "assistant" ? "model" : message[:role]
          { role: role, parts: [{ text: message[:content] }] }
        end
        { messages: new_messages, system: system_prompt[:content] }
      end

      # Legacy: Reset the assistant's messages.
      def reset_assistant_messages(assistant:, system_prompt:, messages:)
        assistant.clear_messages!
        assistant.instructions = system_prompt
        messages.each do |message|
          role = message[:role]
          role = "model" if role == "assistant"
          assistant.add_message(role: role, content: message[:content])
        end
      end
    end
  end
end
