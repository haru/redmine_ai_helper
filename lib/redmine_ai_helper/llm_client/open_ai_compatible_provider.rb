# frozen_string_literal: true

require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # OpenAiCompatibleProvider configures RubyLLM for OpenAI-compatible LLM endpoints.
    class OpenAiCompatibleProvider < RedmineAiHelper::LlmClient::BaseProvider
      # Create a RubyLLM::Chat instance for OpenAI-compatible endpoints.
      # Overrides base class to use provider: :openai and assume_model_exists: true.
      # @param instructions [String, nil] system prompt
      # @param tools [Array<Class>] tool classes to attach
      # @param schema [Hash, nil] Unused: OpenAI-compatible providers have no
      #   provider slug, so native structured output is never selected (the
      #   keyword is accepted only for signature compatibility).
      # @return [RubyLLM::Chat]
      def create_chat(instructions: nil, tools: [], schema: nil) # rubocop:disable Lint/UnusedMethodArgument
        chat = context.chat(
          model: model_name,
          provider: :openai,
          assume_model_exists: true
        )
        chat.with_instructions(instructions) if instructions
        chat.with_tools(*tools) unless tools.empty?
        chat.with_temperature(temperature) if temperature
        apply_user_identifier(chat)
        chat
      end

      protected

      # Build a RubyLLM::Context with custom API base URL and key.
      # @return [RubyLLM::Context]
      def build_context
        profile = resolved_model_profile
        raise "Model Profile not found" unless profile
        raise "Base URI not found" unless profile.base_uri
        RubyLLM.context do |config|
          config.openai_api_key = profile.access_key
          config.openai_api_base = profile.base_uri
          config.openai_use_system_role = true
          configure_http_proxy(config)
        end
      end
    end
  end
end
