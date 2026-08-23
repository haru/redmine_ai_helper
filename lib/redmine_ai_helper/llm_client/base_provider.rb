# frozen_string_literal: true

module RedmineAiHelper
  # LLM provider implementations for different AI services.
  module LlmClient
    # BaseProvider is an abstract class that defines the interface for LLM providers.
    # Each subclass configures RubyLLM with the appropriate API keys and settings.
    class BaseProvider
      include RedmineAiHelper::Logger

      # Mutex used to prevent duplicate model fetches under concurrent requests.
      FETCH_MUTEX = Mutex.new

      # @param model_profile [AiHelperModelProfile, nil] Explicit profile to use.
      #   When nil, falls back to the current AiHelperSetting#model_profile.
      #   Pass an explicit profile when instantiating a provider for a non-default
      #   profile (e.g. the Think model profile).
      # @param request_options [Hash, nil] Per-context HTTP overrides applied on
      #   top of the RubyLLM global configuration. Recognised keys are
      #   +:request_timeout+ (seconds) and +:max_retries+. When nil, the global
      #   configuration is used unchanged.
      def initialize(model_profile: nil, request_options: nil)
        @model_profile = model_profile
        @request_options = request_options
      end

      # Returns the memoized RubyLLM::Context for this provider instance.
      # On first call, ensures the model is registered in the RubyLLM registry
      # before building the context.
      # @return [RubyLLM::Context] provider-specific configuration context
      def context
        @context ||= begin
          ensure_model_registered!
          apply_request_options(build_context)
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
      # @param schema [Hash, nil] native structured-output payload
      #   (`{ name:, schema:, strict: }`). When provided, `chat.with_schema` is
      #   applied to enforce the schema at the provider API level.
      # @return [RubyLLM::Chat]
      def create_chat(instructions: nil, tools: [], schema: nil)
        chat = context.chat(model: model_name)
        chat.with_instructions(instructions) if instructions
        chat.with_tools(*tools) unless tools.empty?
        chat.with_temperature(temperature) if temperature
        chat.with_schema(schema) if schema
        apply_user_identifier(chat)
        chat
      end

      # Whether the configured model supports native structured output.
      #
      # Returns false when the provider slug is unknown (Azure OpenAI,
      # OpenAI-compatible) or the model is not registered. Otherwise returns
      # the model's `structured_output?` capability. Judgment failures fall to
      # the safe (non-native) side.
      # @return [Boolean]
      def supports_structured_output?
        return false if ruby_llm_provider_slug.nil?
        model = RubyLLM.models.by_provider(ruby_llm_provider_slug).all.find { |m| m.id == model_name }
        model&.structured_output? ? true : false
      rescue => e
        ai_helper_logger.warn "supports_structured_output? judgment failed, falling back to false: #{e.message}"
        false
      end

      # Generate an embedding vector for the given text via the memoized context.
      # When ruby_llm_provider_class is nil (OpenAI-compatible providers such as Azure/OpenAI Compatible), the embedding
      # model may not exist in RubyLLM's static registry (e.g. Ollama models such as "nomic-embed-text:latest"),
      # so we explicitly bypass the registry check.
      # @param text [String] text to embed
      # @return [Array<Float>] embedding vector
      def embed(text)
        setting = AiHelperSetting.find_or_create
        embedding_model = setting.embedding_model
        opts = {}
        if ruby_llm_provider_class.nil?
          opts[:provider] = :openai
          opts[:assume_model_exists] = true
        end
        if embedding_model.blank?
          context.embed(text, **opts).vectors
        else
          context.embed(text, model: embedding_model, **opts).vectors
        end
      end

      protected

      # Applies the current user's Redmine ID to the chat request if the
      # send_user_id_enabled setting is active and the provider supports the field.
      # @param chat [RubyLLM::Chat] the chat instance to annotate
      # @return [RubyLLM::Chat] the same chat instance
      def apply_user_identifier(chat)
        return chat unless AiHelperSetting.send_user_id_enabled?
        return chat unless supports_user_identifier?

        chat.with_params(user: User.current.id.to_s)
        chat
      end

      # Returns whether this provider's API accepts the `user` request field.
      # Override to return false for providers that reject unknown top-level fields.
      # @return [Boolean]
      def supports_user_identifier?
        true
      end

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

      # Configure HTTP proxy for the current profile if present.
      # @param config [RubyLLM::Configuration]
      def configure_http_proxy(config)
        proxy = resolved_model_profile&.http_proxy
        config.http_proxy = proxy if proxy.present? && config.respond_to?(:http_proxy=)
      end

      # Build a RubyLLM::Context with provider-specific configuration.
      # Must be implemented by subclasses.
      # @return [RubyLLM::Context] provider-specific configuration context
      def build_context
        raise NotImplementedError, "Subclasses must implement build_context"
      end

      # Applies the per-context HTTP overrides given at construction time.
      # RubyLLM.context duplicates the global configuration, so writing to
      # context.config affects this context only.
      # @param context [RubyLLM::Context] the context built by the subclass
      # @return [RubyLLM::Context] the same context
      def apply_request_options(context)
        return context unless @request_options

        context.config.request_timeout = @request_options[:request_timeout] if @request_options.key?(:request_timeout)
        context.config.max_retries = @request_options[:max_retries] if @request_options.key?(:max_retries)
        context
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
          append_to_model_registry(model_info)
        end
      end

      # Appends a single model to the RubyLLM model registry.
      # RubyLLM 1.x does not expose a public API for adding individual models, so
      # this method accesses the internal @models array directly.  It is isolated
      # here so that any future public API can be adopted in a single place.
      # @param model_info [RubyLLM::Model::Info] model to register
      def append_to_model_registry(model_info)
        RubyLLM.models.instance_variable_get(:@models) << model_info
      end
    end
  end
end
