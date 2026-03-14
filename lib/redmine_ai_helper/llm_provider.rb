# frozen_string_literal: true
require_relative "llm_client/open_ai_provider"
require_relative "llm_client/anthropic_provider"
require_relative "llm_client/gemini_provider"
require_relative "llm_client/azure_open_ai_provider"
require_relative "llm_client/open_ai_compatible_provider"

module RedmineAiHelper
  # This class is responsible for providing the appropriate LLM client based on the LLM type.
  class LlmProvider
    # OpenAI provider constant
    LLM_OPENAI = "OpenAI".freeze
    # OpenAI Compatible provider constant
    LLM_OPENAI_COMPATIBLE = "OpenAICompatible".freeze
    # Gemini provider constant
    LLM_GEMINI = "Gemini".freeze
    # Anthropic provider constant
    LLM_ANTHROPIC = "Anthropic".freeze
    # Azure OpenAI provider constant
    LLM_AZURE_OPENAI = "AzureOpenAi".freeze
    class << self
      # Returns an instance of the appropriate LLM client based on the system settings.
      # @return [Object] An instance of the appropriate LLM client.
      def get_llm_provider
        setting = AiHelperSetting.find_or_create
        get_provider_for_profile(setting.model_profile)
      end

      # Returns an LLM provider instance for the Think model, or nil if not configured.
      # nil return means BaseAgent#think_chat will delegate to chat().
      # Raises ActiveRecord::RecordNotFound if use_think_model is true but the
      # referenced profile no longer exists.
      # @return [Object, nil] An instance of the appropriate LLM client, or nil.
      def get_think_llm_provider
        setting = AiHelperSetting.find_or_create
        return nil unless setting.use_think_model? && setting.think_model_profile_id.present?
        profile = AiHelperModelProfile.find(setting.think_model_profile_id)
        get_provider_for_profile(profile)
      end

      # Returns the LLM type based on the system settings.
      # @return [String] The LLM type (e.g., LLM_OPENAI).
      def type
        setting = AiHelperSetting.find_or_create
        setting.model_profile.llm_type
      end

      private

      # Instantiates the correct provider for a given AiHelperModelProfile.
      # @param profile [AiHelperModelProfile] The model profile to use.
      # @return [Object] An instance of the appropriate LLM client.
      def get_provider_for_profile(profile)
        case profile.llm_type
        when LLM_OPENAI
          return RedmineAiHelper::LlmClient::OpenAiProvider.new(model_profile: profile)
        when LLM_OPENAI_COMPATIBLE
          return RedmineAiHelper::LlmClient::OpenAiCompatibleProvider.new(model_profile: profile)
        when LLM_GEMINI
          return RedmineAiHelper::LlmClient::GeminiProvider.new(model_profile: profile)
        when LLM_ANTHROPIC
          return RedmineAiHelper::LlmClient::AnthropicProvider.new(model_profile: profile)
        when LLM_AZURE_OPENAI
          return RedmineAiHelper::LlmClient::AzureOpenAiProvider.new(model_profile: profile)
        else
          raise NotImplementedError, "LLM provider not found"
        end
      end

      public

      # Returns the options to display in the settings screen's dropdown menu
      # @return [Array] An array of options for the select menu.
      def option_for_select
        [
          ["OpenAI", LLM_OPENAI],
          ["OpenAI Compatible(Experimental)", LLM_OPENAI_COMPATIBLE],
          ["Gemini(Experimental)", LLM_GEMINI],
          ["Anthropic", LLM_ANTHROPIC],
          ["Azure OpenAI(Experimental)", LLM_AZURE_OPENAI],
        ]
      end
    end
  end
end
