# Project-specific settings for AI Helper plugin
class AiHelperProjectSetting < ApplicationRecord
  # Get or create settings for a project
  # @param project [Project] The project to get settings for
  # @return [AiHelperProjectSetting] The project settings
  def self.settings(project)
    setting = AiHelperProjectSetting.where(project_id: project.id).first
    if setting.nil?
      setting = AiHelperProjectSetting.new
      setting.project_id = project.id
      setting.save!
    end
    setting
  end
end
