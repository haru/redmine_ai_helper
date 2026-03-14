require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/issue_json"

class RedmineAiHelper::Util::IssueJsonTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :attachments, :changesets, :journals, :journal_details, :changes, :issue_relations

  context "generate_issue_data" do
    setup do
      @issue = Issue.first
      @issue.assigned_to = User.find(2)

      @issue.status = IssueStatus.find(2)
      @issue.save!
      issue2 = Issue.find(2)
      issue2.parent = @issue
      issue2.save!
      @issue.reload
      changeset = Changeset.first
      changeset.issues << @issue
      changeset.save!
      attachment = Attachment.find(1)
      attachment.container = @issue
      attachment.save!
      @issue.reload
      @test_class = TestClass.new
      @issue.due_date = Date.today + 7
    end

    should "generate correct issue data" do
      issue_data = @test_class.generate_issue_data(@issue)
      # puts JSON.pretty_generate(issue_data)

      assert_equal @issue.id, issue_data[:id]
      assert_equal @issue.subject, issue_data[:subject]
      assert_equal @issue.project.id, issue_data[:project][:id]
      assert_equal @issue.project.name, issue_data[:project][:name]
      assert_equal @issue.tracker.id, issue_data[:tracker][:id]
      assert_equal @issue.tracker.name, issue_data[:tracker][:name]
      assert_equal @issue.status.id, issue_data[:status][:id]
      assert_equal @issue.status.name, issue_data[:status][:name]
      assert_equal @issue.priority.id, issue_data[:priority][:id]
      assert_equal @issue.priority.name, issue_data[:priority][:name]
      assert_equal @issue.author.id, issue_data[:author][:id]
      assert_equal @issue.assigned_to.id, issue_data[:assigned_to][:id]
      assert_equal @issue.description, issue_data[:description]
      assert_equal @issue.start_date, issue_data[:start_date]
      assert_equal @issue.due_date, issue_data[:due_date]
      assert_equal @issue.done_ratio, issue_data[:done_ratio]
      assert_equal @issue.is_private, issue_data[:is_private]
      assert_equal @issue.estimated_hours, issue_data[:estimated_hours]
      assert_equal @issue.created_on.to_s, issue_data[:created_on].to_s
      assert_equal @issue.updated_on.to_s, issue_data[:updated_on].to_s
    end

    should "include type 'image' for image attachments" do
      Attachment.any_instance.stubs(:filename).returns("screenshot.png")

      issue_data = @test_class.generate_issue_data(@issue)
      attachment_data = issue_data[:attachments].first

      assert_equal "image", attachment_data[:type]
    end

    should "include type 'document' for document attachments" do
      Attachment.any_instance.stubs(:filename).returns("report.pdf")

      issue_data = @test_class.generate_issue_data(@issue)
      attachment_data = issue_data[:attachments].first

      assert_equal "document", attachment_data[:type]
    end

    should "include type 'code' for code attachments" do
      Attachment.any_instance.stubs(:filename).returns("script.rb")

      issue_data = @test_class.generate_issue_data(@issue)
      attachment_data = issue_data[:attachments].first

      assert_equal "code", attachment_data[:type]
    end

    should "include type 'audio' for audio attachments" do
      Attachment.any_instance.stubs(:filename).returns("recording.mp3")

      issue_data = @test_class.generate_issue_data(@issue)
      attachment_data = issue_data[:attachments].first

      assert_equal "audio", attachment_data[:type]
    end

    should "include type nil for unsupported attachments" do
      Attachment.any_instance.stubs(:filename).returns("archive.zip")

      issue_data = @test_class.generate_issue_data(@issue)
      attachment_data = issue_data[:attachments].first

      assert_nil attachment_data[:type]
    end

    should "not include disk_path in attachments" do
      issue_data = @test_class.generate_issue_data(@issue)

      issue_data[:attachments].each do |attachment_data|
        assert_not_includes attachment_data.keys, :disk_path,
          "Attachment data must not contain disk_path for security reasons"
      end
    end

    should "include parent field with id and subject when issue has a parent" do
      child_issue = Issue.find(2)
      issue_data = @test_class.generate_issue_data(child_issue)

      assert_not_nil issue_data[:parent]
      assert_equal @issue.id, issue_data[:parent][:id]
      assert_equal @issue.subject, issue_data[:parent][:subject]
    end

    should "set parent field to nil when issue has no parent" do
      issue_data = @test_class.generate_issue_data(@issue)

      assert_nil issue_data[:parent]
    end

    should "include other_issue_id and other_issue_subject in relations" do
      target_issue = Issue.find(3)
      IssueRelation.create!(issue_from_id: @issue.id, issue_to_id: target_issue.id, relation_type: "relates")
      @issue.reload

      issue_data = @test_class.generate_issue_data(@issue)
      relation_data = issue_data[:relations].find { |r| r[:issue_to_id] == target_issue.id }

      assert_not_nil relation_data
      assert_equal target_issue.id, relation_data[:other_issue_id]
      assert_equal target_issue.subject, relation_data[:other_issue_subject]
    end

    should "set other_issue_id correctly when issue is the issue_to in the relation" do
      source_issue = Issue.find(3)
      # Use "blocks" to avoid the relates-type ID normalization (which swaps from/to when from_id > to_id)
      IssueRelation.create!(issue_from_id: source_issue.id, issue_to_id: @issue.id, relation_type: "blocks")
      @issue.reload

      issue_data = @test_class.generate_issue_data(@issue)
      relation_data = issue_data[:relations].find { |r| r[:issue_from_id] == source_issue.id }

      assert_not_nil relation_data
      assert_equal source_issue.id, relation_data[:other_issue_id]
      assert_equal source_issue.subject, relation_data[:other_issue_subject]
    end
  end

  class TestClass < RedmineAiHelper::BaseTools
    # This class is used to test the IssueJson module
    # It includes the IssueJson module to access its methods
    include RedmineAiHelper::Util::IssueJson
  end
end
