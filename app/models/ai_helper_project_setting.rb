# Project-specific settings for AI Helper plugin
class AiHelperProjectSetting < ApplicationRecord
  validates :project_id, presence: true, uniqueness: true

  # Get or create settings for a project
  # @param project [Project] The project to get settings for
  # @return [AiHelperProjectSetting] The project settings
  def self.settings(project)
    AiHelperProjectSetting.find_or_create_by!(project_id: project.id)
  end
end
