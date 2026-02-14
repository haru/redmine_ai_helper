# frozen_string_literal: true
require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # AzureOpenAiProvider configures RubyLLM for Azure OpenAI API access.
    # Uses OpenAI-compatible endpoint with custom base URL.
    class AzureOpenAiProvider < RedmineAiHelper::LlmClient::BaseProvider
      # Configure RubyLLM with Azure OpenAI endpoint and API key.
      # Azure OpenAI is accessed via the OpenAI-compatible interface.
      # @return [void]
      def configure_ruby_llm
        setting = AiHelperSetting.find_or_create
        model_profile = setting.model_profile
        raise "Model Profile not found" unless model_profile
        RubyLLM.configure do |config|
          config.openai_api_key = model_profile.access_key
          config.openai_api_base = model_profile.base_uri
        end
      end

      # Create a RubyLLM::Chat instance for Azure OpenAI.
      # Overrides base class to use provider: :openai and assume_model_exists: true.
      # @param instructions [String, nil] system prompt
      # @param tools [Array<Class>] tool classes to attach
      # @return [RubyLLM::Chat]
      def create_chat(instructions: nil, tools: [])
        configure_ruby_llm
        chat = RubyLLM.chat(
          model: model_name,
          provider: :openai,
          assume_model_exists: true,
        )
        chat.with_instructions(instructions) if instructions
        chat.with_tools(*tools) unless tools.empty?
        chat.with_temperature(temperature) if temperature
        chat
      end
      # Legacy: Generate a Langchain LLM client for backward compatibility.
      # Will be removed after full migration to ruby_llm.
      # @return [RedmineAiHelper::LangfuseUtil::AzureOpenAi] client
      def generate_client
        setting = AiHelperSetting.find_or_create
        model_profile = setting.model_profile
        raise "Model Profile not found" unless model_profile
        llm_options = {
          api_type: :azure,
          chat_deployment_url: model_profile.base_uri,
          embedding_deployment_url: setting.embedding_url,
          api_version: "2024-12-01-preview",
        }
        llm_options[:organization_id] = model_profile.organization_id if model_profile.organization_id
        llm_options[:embedding_model] = setting.embedding_model unless setting.embedding_model.blank?
        llm_options[:organization_id] = model_profile.organization_id if model_profile.organization_id
        llm_options[:max_tokens] = setting.max_tokens if setting.max_tokens
        default_options = {
          model: model_profile.llm_model,
          chat_model: model_profile.llm_model,
          temperature: model_profile.temperature,
          embedding_deployment_url: setting.embedding_url,
        }
        default_options[:embedding_model] = setting.embedding_model unless setting.embedding_model.blank?
        default_options[:max_tokens] = setting.max_tokens if setting.max_tokens
        client = RedmineAiHelper::LangfuseUtil::AzureOpenAi.new(
          api_key: model_profile.access_key,
          llm_options: llm_options,
          default_options: default_options,
          chat_deployment_url: model_profile.base_uri,
          embedding_deployment_url: setting.embedding_url,
        )
        raise "OpenAI LLM Create Error" unless client
        client
      end
    end
  end
end
