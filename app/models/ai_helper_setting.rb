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
    "read_only_mode",
    "all_projects_scope",
    "log_access_enabled",
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

    # Returns whether read-only mode is enabled.
    # @return [Boolean]
    def read_only_mode?
      setting.read_only_mode
    end

    # Returns whether all-projects data-access scope is enabled (FR-004).
    # When true, projects without the ai_helper module enabled are also within the
    # data-access scope, subject to standard Redmine permissions.
    # @return [Boolean]
    def all_projects_scope?
      setting.all_projects_scope
    end

    # Returns whether administrators may read the Redmine and AI Helper log files
    # through the SystemTools log functions (FR-002a).
    # @return [Boolean]
    def log_access_enabled?
      setting.log_access_enabled
    end

    # Returns whether vector search is effectively enabled for the given project.
    # Vector-dependent features (similar-issue search, wiki vector tools,
    # assignment suggestion) use this for per-project gating (FR-012).
    # Delegates the scope decision to the same #vector_target? predicate that
    # drives vector registration/cleanup, so feature gating and registration
    # scope agree by construction for every project.
    # @param project [Project, nil] The project context
    # @return [Boolean] true only when vector search is enabled globally and the
    #   project is within the registration scope.
    def vector_search_enabled_for?(project)
      current = setting
      return false unless current.vector_search_enabled
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

  # Project statuses eligible for vector registration when all_projects_scope is on.
  # Archived projects are out of scope per spec (FR-016) and projects queued for
  # deletion (STATUS_SCHEDULED_FOR_DELETION) are excluded too: Project.visible_condition
  # denies them at query time, so embedding their content could never be retrieved.
  # Closed projects stay included: they remain readable in Redmine.
  VECTOR_SCOPE_PROJECT_STATUSES = [ Project::STATUS_ACTIVE, Project::STATUS_CLOSED ].freeze

  # Base scope of projects eligible for vector registration: every project in a
  # registerable status when all_projects_scope is enabled (FR-016), otherwise those
  # with the ai_helper module enabled (see ADR-002).
  # @return [ActiveRecord::Relation] projects within the vector registration scope
  def vector_scope_projects
    return Project.where(status: VECTOR_SCOPE_PROJECT_STATUSES) if all_projects_scope?
    Project.joins(:enabled_modules).where(enabled_modules: { name: "ai_helper" })
  end

  # The effective set of projects whose issues/wiki are registered in the
  # vector database. Single source of truth shared by the registration rake
  # task and the deletion check (FR-005/FR-008/FR-009/FR-015).
  # @return [ActiveRecord::Relation] selection ∩ vector-scope projects when
  #   register_all is OFF; all vector-scope projects when ON.
  def vector_target_projects_relation
    base = vector_scope_projects
    return base if vector_register_all_projects?
    base.where(id: vector_target_project_ids)
  end

  # Whether the given project is within the vector registration scope (FR-009/FR-016).
  # Mirrors #vector_scope_projects branch by branch, so the per-project check and
  # the relation used by the rake task cannot disagree:
  # - all_projects_scope ON: status gate applies (FR-016)
  # - OFF (legacy, ADR-002): module-enabled projects of any status, no status filter
  # @param project [Project, nil] The project to check
  # @return [Boolean]
  def vector_target?(project)
    return false unless project
    in_scope = if all_projects_scope?
                 VECTOR_SCOPE_PROJECT_STATUSES.include?(project.status)
    else
                 project.module_enabled?(:ai_helper)
    end
    return false unless in_scope
    return true if vector_register_all_projects?
    vector_target_project_ids.include?(project.id)
  end
end
