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
        case type
        when LLM_OPENAI
          return RedmineAiHelper::LlmClient::OpenAiProvider.new
        when LLM_OPENAI_COMPATIBLE
          return RedmineAiHelper::LlmClient::OpenAiCompatibleProvider.new
        when LLM_GEMINI
          return RedmineAiHelper::LlmClient::GeminiProvider.new
        when LLM_ANTHROPIC
          return RedmineAiHelper::LlmClient::AnthropicProvider.new
        when LLM_AZURE_OPENAI
          return RedmineAiHelper::LlmClient::AzureOpenAiProvider.new
        else
          raise NotImplementedError, "LLM provider not found"
        end
      end

      # Returns the LLM type based on the system settings.
      # @return [String] The LLM type (e.g., LLM_OPENAI).
      def type
        setting = AiHelperSetting.find_or_create
        setting.model_profile.llm_type
      end

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
