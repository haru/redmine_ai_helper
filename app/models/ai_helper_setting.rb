# frozen_string_literal: true
#
# AiHelperSetting model for storing settings related to AI helper
class AiHelperSetting < ApplicationRecord
  include Redmine::SafeAttributes
  belongs_to :model_profile, class_name: "AiHelperModelProfile"
  validates :vector_search_uri, :presence => true, if: :vector_search_enabled?
  validates :vector_search_uri, :format => { with: URI::regexp(%w[http https]), message: l("ai_helper.model_profiles.messages.must_be_valid_url") }, if: :vector_search_enabled?

  safe_attributes "model_profile_id", "additional_instructions", "version", "vector_search_enabled", "vector_search_uri", "vector_search_api_key", "embedding_model", "dimension", "vector_search_index_name", "vector_search_index_type", "embedding_url",
    "attachment_send_enabled", "attachment_max_size_mb"

  validates :attachment_max_size_mb,
    numericality: { only_integer: true, greater_than_or_equal_to: 1 },
    if: :attachment_send_enabled?

  class << self
    # This method is used to find or create an AiHelperSetting record.
    # It first tries to find the first record in the AiHelperSetting table.
    def find_or_create
      data = AiHelperSetting.order(:id).first
      data || AiHelperSetting.create!
    end

    # Get the current AI Helper settings
    # @return [AiHelperSetting] The global settings
    def setting
      find_or_create
    end

    def vector_search_enabled?
      setting.vector_search_enabled
    end

    def attachment_send_enabled?
      setting.attachment_send_enabled?
    end

    # Returns the maximum attachment size in megabytes from the global setting.
    # @return [Integer] maximum size in megabytes
    def attachment_max_size_mb
      setting.attachment_max_size_mb
    end
  end

  def attachment_send_enabled?
    attachment_send_enabled
  end

  # Returns true if embedding_url is required
  # @return [Boolean] Whether embedding URL is enabled
  def embedding_url_enabled?
    model_profile&.llm_type == RedmineAiHelper::LlmProvider::LLM_AZURE_OPENAI
  end

  # Get the maximum tokens from the model profile
  # @return [Integer, nil] The maximum tokens or nil if not configured
  def max_tokens
    return nil unless model_profile&.max_tokens
    return nil if model_profile.max_tokens <= 0
    model_profile.max_tokens
  end
end
