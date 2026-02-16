# frozen_string_literal: true

module RedmineAiHelper
  # Provides the appropriate assistant instance.
  # ruby_llm absorbs provider differences internally, so no Gemini-specific assistant is needed.
  class AssistantProvider
    class << self
      # Returns an instance of the assistant using the LLM provider.
      # @param llm_provider [Object] The LLM provider that creates the chat.
      # @param instructions [String] The instructions for the assistant.
      # @param tools [Array] The tool classes to be used by the assistant.
      # @return [RedmineAiHelper::Assistant] An assistant instance.
      def get_assistant(llm_provider:, instructions:, tools: [])
        chat = llm_provider.create_chat(
          instructions: instructions,
          tools: tools,
        )
        RedmineAiHelper::Assistant.new(
          chat: chat,
          instructions: instructions,
          tools: tools,
        )
      end
    end
  end
end
