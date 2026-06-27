require_relative "../../test_helper"

class AiHelperVectorTargetProjectTest < ActiveSupport::TestCase
  fixtures :projects, :enabled_modules

  setup do
    AiHelperSetting.destroy_all
    @setting = AiHelperSetting.setting
    @project = Project.find(1)
  end

  teardown do
    AiHelperSetting.destroy_all
  end

  context "associations" do
    should "belong to setting and project" do
      link = AiHelperVectorTargetProject.create!(setting: @setting, project: @project)
      assert_equal @setting, link.setting
      assert_equal @project, link.project
    end
  end

  context "validations" do
    should "require ai_helper_setting_id" do
      link = AiHelperVectorTargetProject.new(project: @project)
      assert_not link.valid?
      assert_predicate link.errors[:ai_helper_setting_id], :any?
    end

    should "require project_id" do
      link = AiHelperVectorTargetProject.new(setting: @setting)
      assert_not link.valid?
      assert_predicate link.errors[:project_id], :any?
    end

    should "enforce uniqueness of project scoped to setting" do
      AiHelperVectorTargetProject.create!(setting: @setting, project: @project)
      dup = AiHelperVectorTargetProject.new(setting: @setting, project: @project)
      assert_not dup.valid?
      assert_predicate dup.errors[:project_id], :any?
    end
  end

  context "project destruction" do
    should "remove the join row when the selected project is destroyed" do
      project = Project.find(2)
      AiHelperVectorTargetProject.create!(setting: @setting, project: project)
      assert_equal 1, AiHelperVectorTargetProject.where(project_id: project.id).count

      project.destroy

      assert_equal 0, AiHelperVectorTargetProject.where(project_id: project.id).count
    end
  end
end
