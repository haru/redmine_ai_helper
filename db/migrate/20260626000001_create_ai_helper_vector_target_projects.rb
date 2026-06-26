# frozen_string_literal: true

# Join table holding the projects selected for vector registration when
# "register all projects" is OFF. One row = one selected project.
class CreateAiHelperVectorTargetProjects < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_helper_vector_target_projects do |t|
      t.references :ai_helper_setting, null: false, index: true
      t.references :project, null: false, index: true
      t.timestamps
    end

    add_index :ai_helper_vector_target_projects,
              [ :ai_helper_setting_id, :project_id ],
              unique: true,
              name: "index_ai_helper_vector_target_projects_unique"
    add_foreign_key :ai_helper_vector_target_projects, :projects, on_delete: :cascade
    add_foreign_key :ai_helper_vector_target_projects, :ai_helper_settings, on_delete: :cascade
  end
end
