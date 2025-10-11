class AiHelperHealthReport < ApplicationRecord
  include Redmine::SafeAttributes

  belongs_to :project
  belongs_to :user

  # Validations
  validates :project_id, presence: true
  validates :user_id, presence: true
  validates :health_report, presence: true

  # Scopes
  scope :sorted, -> { order(created_at: :desc) }
  scope :visible, -> { includes(:project).where(projects: { status: Project::STATUS_ACTIVE }) }
  scope :for_project, ->(project_id) { where(project_id: project_id) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :recent, ->(limit = 10) { sorted.limit(limit) }

  # Accessor for metrics
  def metrics_hash
    return {} if metrics.blank?
    JSON.parse(metrics) rescue {}
  end

  def metrics_hash=(hash)
    self.metrics = hash.to_json
  end

  # Check if the report is visible to the user
  def visible?(user = User.current)
    return false unless project.present? && user.present?
    # User can view report if they have AI Helper access to the project
    user.allowed_to?(:view_ai_helper, project)
  end

  # Check if the report can be deleted by the user
  def deletable?(user = User.current)
    return false unless project.present? && user.present?
    # Report creator or admin can delete if they have AI Helper access
    (user.id == user_id || user.admin?) &&
      user.allowed_to?(:view_ai_helper, project)
  end
end
