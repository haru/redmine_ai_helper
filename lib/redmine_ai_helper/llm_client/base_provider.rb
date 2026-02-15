# frozen_string_literal: true
module RedmineAiHelper
  # LLM provider implementations for different AI services.
  module LlmClient
    # BaseProvider is an abstract class that defines the interface for LLM providers.
    # Each subclass configures RubyLLM with the appropriate API keys and settings.
    class BaseProvider

      # Returns the memoized RubyLLM::Context for this provider instance.
      # The context is created once via build_context and reused for all
      # subsequent chat and embed calls within the same request lifecycle.
      # @return [RubyLLM::Context] provider-specific configuration context
      def context
        @context ||= build_context
      end

      # Get the model name from the current model profile.
      # @return [String] model name
      def model_name
        setting = AiHelperSetting.find_or_create
        model_profile = setting.model_profile
        raise "Model Profile not found" unless model_profile
        model_profile.llm_model
      end

      # Get the temperature from the current model profile.
      # @return [Float, nil] temperature
      def temperature
        setting = AiHelperSetting.find_or_create
        model_profile = setting.model_profile
        model_profile&.temperature
      end

      # Get the max_tokens from the current setting.
      # @return [Integer, nil] max_tokens
      def max_tokens
        setting = AiHelperSetting.find_or_create
        setting.max_tokens
      end

      # Create a RubyLLM::Chat instance via the memoized context.
      # @param instructions [String, nil] system prompt
      # @param tools [Array<Class>] tool classes to attach
      # @return [RubyLLM::Chat]
      def create_chat(instructions: nil, tools: [])
        chat = context.chat(model: model_name)
        chat.with_instructions(instructions) if instructions
        chat.with_tools(*tools) unless tools.empty?
        chat.with_temperature(temperature) if temperature
        chat
      end

      # Generate an embedding vector for the given text via the memoized context.
      # @param text [String] text to embed
      # @return [Array<Float>] embedding vector
      def embed(text)
        setting = AiHelperSetting.find_or_create
        embedding_model = setting.embedding_model
        if embedding_model.blank?
          context.embed(text).vectors
        else
          context.embed(text, model: embedding_model).vectors
        end
      end

      protected

      # Build a RubyLLM::Context with provider-specific configuration.
      # Must be implemented by subclasses.
      # @return [RubyLLM::Context] provider-specific configuration context
      def build_context
        raise NotImplementedError, "Subclasses must implement build_context"
      end
    end
  end
end
