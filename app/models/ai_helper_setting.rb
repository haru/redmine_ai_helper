# frozen_string_literal: true

#
# AiHelperSetting model for storing settings related to AI helper
class AiHelperSetting < ApplicationRecord
  include Redmine::SafeAttributes
  belongs_to :model_profile, class_name: "AiHelperModelProfile"
  belongs_to :think_model_profile, class_name: "AiHelperModelProfile", optional: true
  belongs_to :vector_model_profile, class_name: "AiHelperModelProfile", optional: true
  has_many :vector_target_project_links, class_name: "AiHelperVectorTargetProject", dependent: :destroy, inverse_of: :setting
  has_many :vector_target_projects, through: :vector_target_project_links, source: :project
  validates :vector_search_uri, presence: true, if: :vector_search_enabled?
  validates :vector_search_uri, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: l("ai_helper.model_profiles.messages.must_be_valid_url") }, if: :vector_search_enabled?
  validates :think_model_profile_id, presence: true, if: :use_think_model?
  validates :vector_model_profile_id, presence: true, if: -> { use_vector_model_profile? && vector_search_enabled? }

  before_save :clear_vector_model_profile_id_if_disabled

  safe_attributes "model_profile_id", "additional_instructions", "version", "vector_search_enabled", "vector_search_uri", "vector_search_api_key", "embedding_model", "dimension", "vector_search_index_name", "vector_search_index_type", "embedding_url",
    "attachment_send_enabled", "attachment_max_size_mb",
    "use_think_model", "think_model_profile_id",
    "use_vector_model_profile", "vector_model_profile_id",
    "mcp_server_enabled",
    "send_user_id_enabled",
    "vector_register_all_projects", "vector_target_project_ids"

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

    delegate :attachment_send_enabled?, to: :setting

    # Returns the maximum attachment size in megabytes from the global setting.
    # @return [Integer] maximum size in megabytes
    delegate :attachment_max_size_mb, to: :setting

    # Returns whether the MCP server endpoint is enabled.
    # @return [Boolean]
    def mcp_server_enabled?
      setting.mcp_server_enabled
    end

    # Returns whether sending the user ID to LLM providers is enabled.
    # @return [Boolean]
    def send_user_id_enabled?
      setting.send_user_id_enabled
    end

    # Returns whether vector search is effectively enabled for the given project.
    # Vector-dependent features (similar-issue search, wiki vector tools,
    # assignment suggestion) use this for per-project gating (FR-012).
    # @param project [Project, nil] The project context
    # @return [Boolean] true only when vector search is enabled globally and the
    #   project is within the registration scope.
    def vector_search_enabled_for?(project)
      current = setting
      return false unless current.vector_search_enabled
      return true if current.vector_register_all_projects?
      current.vector_target?(project)
    end
  end

  private

  def clear_vector_model_profile_id_if_disabled
    unless vector_search_enabled?
      self.use_vector_model_profile = false
      self.vector_model_profile_id = nil
      return
    end
    self.vector_model_profile_id = nil unless use_vector_model_profile?
  end

  public

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

  # Base scope of projects eligible for vector registration: those with the
  # ai_helper module enabled (see 019-vector-scope-by-module).
  # @return [ActiveRecord::Relation] ai_helper-module-enabled projects
  def ai_helper_module_projects
    Project.joins(:enabled_modules).where(enabled_modules: { name: "ai_helper" })
  end

  # The effective set of projects whose issues/wiki are registered in the
  # vector database. Single source of truth shared by the registration rake
  # task and the deletion check (FR-005/FR-008/FR-009/FR-015).
  # @return [ActiveRecord::Relation] selection ∩ ai_helper-module projects when
  #   register_all is OFF; all ai_helper-module projects when ON.
  def vector_target_projects_relation
    base = ai_helper_module_projects
    return base if vector_register_all_projects?
    base.where(id: vector_target_project_ids)
  end

  # Whether the given project is within the vector registration scope (FR-009).
  # @param project [Project, nil] The project to check
  # @return [Boolean]
  def vector_target?(project)
    return false unless project
    return false unless project.module_enabled?(:ai_helper)
    return true if vector_register_all_projects?
    vector_target_project_ids.include?(project.id)
  end
end
