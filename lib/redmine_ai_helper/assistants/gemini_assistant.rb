# frozen_string_literal: true
module RedmineAiHelper
  # Assistant implementations for different LLM providers
  module Assistants
    # GeminiAssistant is a specialized assistant for handling Gemini messages.
    class GeminiAssistant < RedmineAiHelper::Assistant
      # Adjust the message format to match Gemini. Convert "assistant" role to "model".
      def add_message(role: "user", content: nil, image_url: nil, tool_calls: [], tool_call_id: nil)
        new_role = role
        case role
        when "assistant"
          new_role = "model"
        end
        super(
          role: new_role,
          content: content,
          image_url: image_url,
          tool_calls: tool_calls,
          tool_call_id: tool_call_id,
        )
      end
    end
  end
end
