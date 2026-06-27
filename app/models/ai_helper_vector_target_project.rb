# frozen_string_literal: true

# Join model holding one selected vector-registration target project per row.
# Used when the global setting's "register all projects" flag is OFF to scope
# which projects' issues/wiki are registered in the vector database.
class AiHelperVectorTargetProject < ApplicationRecord
  belongs_to :setting, class_name: "AiHelperSetting", foreign_key: :ai_helper_setting_id, inverse_of: :vector_target_project_links
  belongs_to :project

  validates :ai_helper_setting_id, presence: true
  validates :project_id, presence: true, uniqueness: { scope: :ai_helper_setting_id }
end
