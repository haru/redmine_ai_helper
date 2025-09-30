# frozen_string_literal: true
module RedmineAiHelper
  module LlmClient
    # GeminiProvider is a specialized provider for handling Google Gemini LLM requests.
    class GeminiProvider < RedmineAiHelper::LlmClient::BaseProvider
      # Generate a new Gemini client using the provided API key and model profile.
      # @return [Langchain::LLM::GoogleGemini] client
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

      # Generate a parameter for chat completion request for the Gemini LLM.
      # @param [Hash] system_prompt
      # @param [Array] messages
      # @return [Hash] chat_params
      def create_chat_param(system_prompt, messages)
        # Maps the messages to the "contents" format expected by Gemini
        new_messages = messages.map do |message|
          # Ensure that the role "assistant" is converted to "model"
          role = message[:role] == "assistant" ? "model" : message[:role]

          {
            role: role,
            parts: [
              {
                text: message[:content],
              },
            ],
          }
        end

        chat_params = {
          messages: new_messages,
          system: system_prompt[:content],
        }

        chat_params
      end

      # Reset the assistant's messages, set the system prompt, and add messages.
      # @param [RedmineAiHelper::Assistant] assistant
      # @param [Hash] system_prompt
      # @param [Array] messages
      # @return [void]
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
