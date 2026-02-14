# frozen_string_literal: true
require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # AnthropicProvider configures RubyLLM for Anthropic API access.
    class AnthropicProvider < RedmineAiHelper::LlmClient::BaseProvider
      # Configure RubyLLM with Anthropic API key.
      # @return [void]
      def configure_ruby_llm
        setting = AiHelperSetting.find_or_create
        model_profile = setting.model_profile
        raise "Model Profile not found" unless model_profile
        RubyLLM.configure do |config|
          config.anthropic_api_key = model_profile.access_key
        end
      end

      # Legacy: Generate a Langchain LLM client for backward compatibility.
      # Will be removed after full migration to ruby_llm.
      # @return [RedmineAiHelper::LangfuseUtil::Anthropic] client
      def generate_client
        setting = AiHelperSetting.find_or_create
        model_profile = setting.model_profile
        raise "Model Profile not found" unless model_profile
        default_options = {
          chat_model: model_profile.llm_model,
          temperature: model_profile.temperature,
          max_tokens: 2000,
        }
        default_options[:max_tokens] = setting.max_tokens if setting.max_tokens
        client = RedmineAiHelper::LangfuseUtil::Anthropic.new(
          api_key: model_profile.access_key,
          default_options: default_options,
        )
        raise "Anthropic LLM Create Error" unless client
        client
      end

      # Legacy: Generate a chat completion request for backward compatibility.
      def create_chat_param(system_prompt, messages)
        new_messages = messages.dup
        chat_params = { messages: new_messages }
        chat_params[:system] = system_prompt[:content]
        chat_params
      end

      # Legacy: Extract a message from the chunk for backward compatibility.
      def chunk_converter(chunk)
        chunk.dig("delta", "text")
      end

      # Legacy: Reset assistant messages for backward compatibility.
      def reset_assistant_messages(assistant:, system_prompt:, messages:)
        assistant.clear_messages!
        assistant.instructions = system_prompt
        messages.each do |message|
          assistant.add_message(role: message[:role], content: message[:content])
        end
      end
    end
  end
end
