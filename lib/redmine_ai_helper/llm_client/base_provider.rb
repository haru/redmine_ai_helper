# frozen_string_literal: true
module RedmineAiHelper
  # LLM client implementations
  module LlmClient
    # BaseProvider is an abstract class that defines the interface for LLM providers.
    class BaseProvider

      # @return LLM Client of the LLM provider.
      def generate_client
        raise NotImplementedError, "LLM provider not found"
      end

      # @return [Hash] The system prompt for the LLM provider.
      def create_chat_param(system_prompt, messages)
        new_messages = messages.dup
        new_messages.unshift(system_prompt)
        {
          messages: new_messages,
        }
      end

      # Extracts a message from the chunk
      # @param [Hash] chunk
      # @return [String] message
      def chunk_converter(chunk)
        chunk.dig("delta", "content")
      end

      # Clears the messages held by the Assistant, sets the system prompt, and adds messages
      # @param [RedmineAiHelper::Assistant] assistant
      # @param [Hash] system_prompt
      # @param [Array] messages
      # @return [void]
      def reset_assistant_messages(assistant:, system_prompt:, messages:)
        assistant.clear_messages!
        assistant.add_message(role: "system", content: system_prompt[:content])
        messages.each do |message|
          assistant.add_message(role: message[:role], content: message[:content])
        end
      end
    end
  end
end
