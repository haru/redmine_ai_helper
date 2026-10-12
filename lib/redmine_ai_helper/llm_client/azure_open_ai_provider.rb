# frozen_string_literal: true

require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # AzureOpenAiProvider configures RubyLLM for Azure OpenAI API access.
    # Uses RubyLLM's :azure provider, which builds the endpoint URL from the
    # configured base URI and selects the API protocol from the deployment name
    # (Responses API for gpt-5.4+ / gpt-6+ names, Chat Completions otherwise).
    class AzureOpenAiProvider < RedmineAiHelper::LlmClient::BaseProvider
      # Create a RubyLLM::Chat instance for Azure OpenAI.
      # Overrides base class to use provider: :azure and assume_model_exists: true.
      # @param instructions [String, Instructions, nil] system prompt
      # @param tools [Array<Class>] tool classes to attach
      # @param schema [Hash, nil] Unused: Azure OpenAI has no provider slug, so
      #   native structured output is never selected (the keyword is accepted
      #   only for signature compatibility with the base class).
      # @return [RubyLLM::Chat]
      def create_chat(instructions: nil, tools: [], schema: nil) # rubocop:disable Lint/UnusedMethodArgument
        chat = context.chat(
          model: model_name,
          provider: :azure,
          assume_model_exists: true
        )
        apply_instructions(chat, instructions)
        chat.with_tools(*tools) unless tools.empty?
        chat.with_temperature(temperature) if temperature
        apply_user_identifier(chat)
        chat
      end

      protected

      # Azure embeddings go through RubyLLM's :azure provider.
      # @return [Symbol]
      def embedding_provider_slug
        :azure
      end

      # Build a RubyLLM::Context with Azure OpenAI endpoint and API key.
      # @return [RubyLLM::Context]
      def build_context
        profile = resolved_model_profile
        raise "Model Profile not found" unless profile
        RubyLLM.context do |config|
          config.azure_api_key = profile.access_key
          config.azure_api_base = profile.base_uri
          configure_http_proxy(config)
        end
      end
    end
  end
end
