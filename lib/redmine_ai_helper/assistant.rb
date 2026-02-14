# frozen_string_literal: true

module RedmineAiHelper
  # Assistant wraps RubyLLM::Chat with a Langchain::Assistant-compatible interface.
  # Provides add_message, run, clear_messages!, messages, and instructions= methods
  # for backward compatibility with existing agent code.
  class Assistant
    attr_accessor :llm_provider, :langfuse
    attr_reader :chat

    def initialize(chat:, instructions: nil, tools: [])
      @chat = chat
      @instructions = instructions
      @tools = tools
    end

    # Add a message to the chat history.
    # @param role [String] The role of the message sender ("user", "assistant", "system").
    # @param content [String] The content of the message.
    def add_message(role:, content:, **_kwargs)
      @chat.add_message(role: role.to_sym, content: content)
    end

    # Run the assistant with automatic tool execution.
    # @param auto_tool_execution [Boolean] Whether to auto-execute tools (always true with ruby_llm).
    # @return [Array] Array containing the response (for Langchain compatibility).
    def run(auto_tool_execution: true)
      messages = @chat.messages
      last_user_message = messages.reverse.find { |m| m.role == :user }
      response = @chat.ask(last_user_message&.content || "")
      [response]
    end

    # Clear all messages from the chat.
    def clear_messages!
      @chat.reset
    end

    # Get all messages in the chat.
    # @return [Array] The messages in the chat.
    def messages
      @chat.messages
    end

    # Set new instructions for the assistant.
    # @param value [String] The new instructions.
    def instructions=(value)
      @instructions = value
    end
  end
end
