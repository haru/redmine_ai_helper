# frozen_string_literal: true

require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # AzureOpenAiProvider configures RubyLLM for Azure OpenAI API access.
    # Uses OpenAI-compatible endpoint with custom base URL.
    class AzureOpenAiProvider < RedmineAiHelper::LlmClient::BaseProvider
      # Create a RubyLLM::Chat instance for Azure OpenAI.
      # Overrides base class to use provider: :openai and assume_model_exists: true.
      # @param instructions [String, nil] system prompt
      # @param tools [Array<Class>] tool classes to attach
      # @param schema [Hash, nil] Unused: Azure OpenAI has no provider slug, so
      #   native structured output is never selected (the keyword is accepted
      #   only for signature compatibility with the base class).
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

      # Build a RubyLLM::Context with Azure OpenAI endpoint and API key.
      # @return [RubyLLM::Context]
      def build_context
        profile = resolved_model_profile
        raise "Model Profile not found" unless profile
        RubyLLM.context do |config|
          config.openai_api_key = profile.access_key
          config.openai_api_base = profile.base_uri
          configure_http_proxy(config)
        end
      end
    end
  end
end
