# frozen_string_literal: true
module RedmineAiHelper
  # LLM provider implementations for different AI services.
  module LlmClient
    # BaseProvider is an abstract class that defines the interface for LLM providers.
    # Each subclass configures RubyLLM with the appropriate API keys and settings.
    class BaseProvider
      FETCH_MUTEX = Mutex.new

      # @param model_profile [AiHelperModelProfile, nil] Explicit profile to use.
      #   When nil, falls back to the current AiHelperSetting#model_profile.
      #   Pass an explicit profile when instantiating a provider for a non-default
      #   profile (e.g. the Think model profile).
      def initialize(model_profile: nil)
        @model_profile = model_profile
      end

      # Returns the memoized RubyLLM::Context for this provider instance.
      # On first call, ensures the model is registered in the RubyLLM registry
      # before building the context.
      # @return [RubyLLM::Context] provider-specific configuration context
      def context
        @context ||= begin
          ensure_model_registered!
          build_context
        end
      end

      # Get the model name from the resolved model profile.
      # @return [String] model name
      def model_name
        profile = resolved_model_profile
        raise "Model Profile not found" unless profile
        profile.llm_model
      end

      # Get the temperature from the resolved model profile.
      # @return [Float, nil] temperature
      def temperature
        resolved_model_profile&.temperature
      end

      # Get the max_tokens from the resolved model profile.
      # @return [Integer, nil] max_tokens
      def max_tokens
        resolved_model_profile&.max_tokens
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

      # Ensures the configured model exists in the RubyLLM registry.
      # If the provider class is nil (Azure / Compatible), skips fetch.
      # If the model is already registered, skips fetch.
      # Otherwise fetches the model list from the provider API and registers it.
      def ensure_model_registered!
        return if ruby_llm_provider_class.nil?
        return if model_in_registry?
        fetch_and_register_model!
      end

      # Returns the model profile to use for this provider instance.
      # Uses the explicit profile passed at construction time, or falls back
      # to the current AiHelperSetting#model_profile.
      # @return [AiHelperModelProfile, nil]
      def resolved_model_profile
        @model_profile || AiHelperSetting.find_or_create.model_profile
      end

      # Returns the RubyLLM provider class for this provider.
      # Override in subclasses that support automatic model fetching.
      # @return [Class, nil]
      def ruby_llm_provider_class
        nil
      end

      # Returns the RubyLLM provider slug string for registry lookups.
      # Override in subclasses that support automatic model fetching.
      # @return [String, nil]
      def ruby_llm_provider_slug
        nil
      end

      # Configures a RubyLLM::Configuration with this provider's API key.
      # No-op by default; override in subclasses that support model fetching.
      # @param config [RubyLLM::Configuration]
      def configure_provider_config(config)
        # no-op
      end

      # Build a RubyLLM::Context with provider-specific configuration.
      # Must be implemented by subclasses.
      # @return [RubyLLM::Context] provider-specific configuration context
      def build_context
        raise NotImplementedError, "Subclasses must implement build_context"
      end

      private

      # Returns true if the configured model is already in the RubyLLM registry
      # for the correct provider, preventing cross-provider false positives.
      def model_in_registry?
        RubyLLM.models.by_provider(ruby_llm_provider_slug).any? { |m| m.id == model_name }
      end

      # Fetches the model list from the provider API using this profile's API key
      # and registers the target model in the RubyLLM registry.
      # Uses a class-level Mutex to prevent duplicate fetches under concurrency.
      def fetch_and_register_model!
        FETCH_MUTEX.synchronize do
          return if model_in_registry?
          config = RubyLLM::Configuration.new
          configure_provider_config(config)
          provider_instance = ruby_llm_provider_class.new(config)
          fetched_models = provider_instance.list_models
          model_info = fetched_models.find { |m| m.id == model_name }
          raise "Model '#{model_name}' not found in provider's model list" unless model_info
          RubyLLM.models.instance_variable_get(:@models) << model_info
        end
      end
    end
  end
end
