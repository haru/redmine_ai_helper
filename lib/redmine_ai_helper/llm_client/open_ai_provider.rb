# frozen_string_literal: true
require "redmine_ai_helper/langfuse_util/open_ai"
require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # OpenAiProvider configures RubyLLM for OpenAI API access.
    class OpenAiProvider < RedmineAiHelper::LlmClient::BaseProvider
      # Configure RubyLLM with OpenAI API key and organization.
      # @return [void]
      def configure_ruby_llm
        setting = AiHelperSetting.find_or_create
        model_profile = setting.model_profile
        raise "Model Profile not found" unless model_profile
        RubyLLM.configure do |config|
          config.openai_api_key = model_profile.access_key
          config.openai_organization_id = model_profile.organization_id if model_profile.organization_id
        end
      end

      # Legacy: Generate a Langchain LLM client for backward compatibility.
      # Will be removed after full migration to ruby_llm.
      # @return [RedmineAiHelper::LangfuseUtil::OpenAi] the OpenAI client
      def generate_client
        setting = AiHelperSetting.find_or_create
        model_profile = setting.model_profile
        raise "Model Profile not found" unless model_profile
        llm_options = {}
        llm_options[:organization_id] = model_profile.organization_id if model_profile.organization_id
        llm_options[:embedding_model] = setting.embedding_model unless setting.embedding_model.blank?
        llm_options[:max_tokens] = setting.max_tokens if setting.max_tokens
        default_options = {
          model: model_profile.llm_model,
          chat_model: model_profile.llm_model,
          temperature: model_profile.temperature,
        }
        default_options[:embedding_model] = setting.embedding_model unless setting.embedding_model.blank?
        default_options[:max_tokens] = setting.max_tokens if setting.max_tokens
        client = RedmineAiHelper::LangfuseUtil::OpenAi.new(
          api_key: model_profile.access_key,
          llm_options: llm_options,
          default_options: default_options,
        )
        raise "OpenAI LLM Create Error" unless client
        client
      end
    end
  end
end
