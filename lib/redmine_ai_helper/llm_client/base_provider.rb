# frozen_string_literal: true
module RedmineAiHelper
  module LlmClient
    # BaseProvider is an abstract class that defines the interface for LLM providers.
    # Each subclass configures RubyLLM with the appropriate API keys and settings.
    class BaseProvider

      # Configure RubyLLM with provider-specific API keys and settings.
      # Must be implemented by subclasses.
      # @return [void]
      def configure_ruby_llm
        raise NotImplementedError, "Subclasses must implement configure_ruby_llm"
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

      # Create a RubyLLM::Chat instance with the given options.
      # @param instructions [String, nil] system prompt
      # @param tools [Array<Class>] tool classes to attach
      # @return [RubyLLM::Chat]
      def create_chat(instructions: nil, tools: [])
        configure_ruby_llm
        chat = RubyLLM.chat(model: model_name)
        chat.with_instructions(instructions) if instructions
        chat.with_tools(*tools) unless tools.empty?
        chat.with_temperature(temperature) if temperature
        chat
      end

      # Generate an embedding vector for the given text.
      # @param text [String] text to embed
      # @return [Array<Float>] embedding vector
      def embed(text)
        configure_ruby_llm
        setting = AiHelperSetting.find_or_create
        embedding_model = setting.embedding_model
        if embedding_model.blank?
          RubyLLM.embed(text).vectors
        else
          RubyLLM.embed(text, model: embedding_model).vectors
        end
      end
    end
  end
end
