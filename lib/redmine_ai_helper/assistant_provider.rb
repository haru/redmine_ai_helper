# frozen_string_literal: true
module RedmineAiHelper
  # Provides the appropriate assistant instance based on the LLM type
  class AssistantProvider
    # This class is responsible for providing the appropriate assistant based on the LLM type.
    class << self
      # Returns an instance of the appropriate assistant based on the LLM type.
      # @param llm_type [String] The type of LLM (e.g., LLM_GEMINI).
      # @param llm [Object] The LLM client to use.
      # @param instructions [String] The instructions for the assistant.
      # @param tools [Array] The tools to be used by the assistant.
      # @return [Object] An instance of the appropriate assistant.
      def get_assistant(llm_type:, llm:, instructions:, tools: [])
        case llm_type
        when LlmProvider::LLM_GEMINI
          return RedmineAiHelper::Assistants::GeminiAssistant.new(
                   llm: llm,
                   instructions: instructions,
                   tools: tools,
                 )
        else
          return RedmineAiHelper::Assistant.new(
                   llm: llm,
                   instructions: instructions,
                   tools: tools,
                 )
        end
      end
    end
  end
end
