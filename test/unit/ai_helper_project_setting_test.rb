require_relative "../test_helper"

class AiHelperProjectSettingTest < ActiveSupport::TestCase
  fixtures :projects

  context ".settings" do
    setup do
      @project = Project.find(1)
    end

    should "create the row when it does not exist yet" do
      assert_difference "AiHelperProjectSetting.count", 1 do
        settings = AiHelperProjectSetting.settings(@project)

        assert_equal @project.id, settings.project_id
      end
    end

    should "return the existing row without creating a new one" do
      existing = AiHelperProjectSetting.settings(@project)

      assert_no_difference "AiHelperProjectSetting.count" do
        assert_equal existing.id, AiHelperProjectSetting.settings(@project).id
      end
    end
  end

  context "issue_summary_instructions" do
    setup do
      @project = Project.find(1)
      @settings = AiHelperProjectSetting.settings(@project)
    end

    should "persist the issue_summary_instructions value" do
      @settings.issue_summary_instructions = "Summarize from the customer's perspective"
      @settings.save!

      assert_equal "Summarize from the customer's perspective", @settings.reload.issue_summary_instructions
    end

    should "default to nil for an existing row" do
      @settings.issue_draft_instructions = "draft instructions"
      @settings.save!

      assert_nil @settings.reload.issue_summary_instructions
    end

    should "be blank for a fresh settings row" do
      assert_nil @settings.issue_summary_instructions
      assert @settings.issue_summary_instructions.blank?
    end
  end
end
