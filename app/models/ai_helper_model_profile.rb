# frozen_string_literal: true
# AiHelperModelProfile model for managing AI Helper model profiles
class AiHelperModelProfile < ApplicationRecord
  include Redmine::SafeAttributes
  validates :name, presence: true, uniqueness: true
  validates :llm_type, presence: true
  validates :access_key, presence: true, if: :access_key_required?
  validates :llm_model, presence: true
  validates :base_uri, presence: true, if: :base_uri_required?
  validates :base_uri, format: { with: URI::regexp(%w[http https]), message: l("ai_helper.model_profiles.messages.must_be_valid_url") }, if: :base_uri_required?
  validates :temperature, presence: true, numericality: { greater_than_or_equal_to: 0.0 }

  safe_attributes "name", "llm_type", "access_key", "organization_id", "base_uri", "version", "llm_model", "temperature", "max_tokens"

  before_validation :handle_gpt5_temperature

  # Replace all characters after the 4th with *
  def masked_access_key
    return access_key if access_key.blank? || access_key.length <= 4
    masked_key = access_key.dup
    masked_key[4..-1] = "*" * (masked_key.length - 4)
    masked_key
  end

  # Returns the String which is displayed in the select box
  def display_name
    "#{name} (#{llm_type}: #{llm_model})"
  end

  # returns true if base_uri is required.
  def base_uri_required?
    # Check if the llm_type is OpenAICompatible
    llm_type == RedmineAiHelper::LlmProvider::LLM_OPENAI_COMPATIBLE ||
      llm_type == RedmineAiHelper::LlmProvider::LLM_AZURE_OPENAI
  end

  # returns true if access_key is required.
  def access_key_required?
    llm_type != RedmineAiHelper::LlmProvider::LLM_OPENAI_COMPATIBLE
  end

  # Returns the LLM type name for display
  def display_llm_type
    names = RedmineAiHelper::LlmProvider.option_for_select
    name = names.find { |n| n[1] == llm_type }
    name ? name[0] : ""
  end

  private

  # Handle GPT-5 series models that don't support temperature parameter
  # Automatically set temperature to 1 for these models before validation
  def handle_gpt5_temperature
    if gpt5_model_requiring_fixed_temperature?
      self.temperature = 1.0
    end
  end

  # Check if the model is a GPT-5 series model that requires temperature=1
  # Returns true for:
  # - Model name is exactly "gpt-5"
  # - Model name starts with "gpt-5-" but does not contain "chat"
  def gpt5_model_requiring_fixed_temperature?
    return false if llm_model.blank?

    model_name = llm_model.downcase.strip

    # Exact match for "gpt-5"
    return true if model_name == "gpt-5"

    # Starts with "gpt-5-" but doesn't contain "chat"
    if model_name.start_with?("gpt-5-")
      return !model_name.include?("chat")
    end

    false
  end
end
