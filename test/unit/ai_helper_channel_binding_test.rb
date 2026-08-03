# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

class AiHelperChannelBindingTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  fixtures :projects

  context "validations" do
    should "require channel_type, channel_id and project" do
      binding = AiHelperChannelBinding.new

      assert_not binding.valid?
      assert_predicate binding.errors[:channel_type], :present?
      assert_predicate binding.errors[:channel_id], :present?
      assert_predicate binding.errors[:project], :present?
    end

    should "be valid with channel_type, channel_id and project" do
      binding = build(:ai_helper_channel_binding, project: Project.find(1))

      assert_predicate binding, :valid?
    end

    should "reject a duplicate channel_id for the same channel_type" do
      create(:ai_helper_channel_binding, channel_id: "C1234567", project: Project.find(1))
      duplicate = build(:ai_helper_channel_binding, channel_id: "C1234567", project: Project.find(2))

      assert_not duplicate.valid?
      assert_predicate duplicate.errors[:channel_id], :present?
    end

    should "allow the same channel_id for a different channel_type" do
      create(:ai_helper_channel_binding, channel_id: "C1234567", project: Project.find(1))
      other = build(:ai_helper_channel_binding, channel_type: "discord", channel_id: "C1234567", project: Project.find(2))

      assert_predicate other, :valid?
    end
  end

  context "for_channel scope" do
    should "return the binding matching channel_type and channel_id" do
      binding = create(:ai_helper_channel_binding, channel_id: "C7654321", project: Project.find(1))

      assert_equal binding, AiHelperChannelBinding.for_channel("slack", "C7654321").first
    end

    should "return no bindings for an unknown channel" do
      create(:ai_helper_channel_binding, channel_id: "C7654321", project: Project.find(1))

      assert_empty AiHelperChannelBinding.for_channel("slack", "C0000000")
    end
  end

  context "project deletion" do
    should "delete bindings when the project is destroyed" do
      project = create(:project)
      binding = create(:ai_helper_channel_binding, project: project)

      project.destroy

      assert_nil AiHelperChannelBinding.find_by(id: binding.id)
    end
  end
end
