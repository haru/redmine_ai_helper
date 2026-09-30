require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/issue_json"

class RedmineAiHelper::Util::IssueJsonTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :attachments, :changesets, :journals, :journal_details, :changes, :issue_relations, :members, :member_roles, :roles, :groups_users

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
      @issue.due_date = Time.zone.today + 7
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

    should "include custom_fields with id, name, and value" do
      custom_field = IssueCustomField.create!(name: "Severity", field_format: "string", is_for_all: true, tracker_ids: Tracker.pluck(:id))
      @issue.custom_field_values = { custom_field.id => "Critical" }
      @issue.save!

      issue_data = @test_class.generate_issue_data(@issue)

      assert issue_data.key?(:custom_fields)
      field_data = issue_data[:custom_fields].find { |f| f[:id] == custom_field.id }
      assert_not_nil field_data
      assert_equal custom_field.name, field_data[:name]
      assert_equal "Critical", field_data[:value]

      custom_field.destroy
    end
  end

  context "generate_issue_data_with_roles" do
    setup do
      @issue = Issue.find(1)
      @test_class = TestClass.new
    end

    should "include all role names of a multi-role user, deduplicated and sorted ascending" do
      MemberRole.create!(member: Member.find(1), role: Role.find(2))

      data = @test_class.generate_issue_data_with_roles(@issue)

      assert_equal %w[Developer Manager], data[:author][:roles]
    end

    should "deduplicate roles shared by direct and group-inherited membership" do
      # The issue author joins a group whose project membership carries the
      # Developer role; Redmine materialises the inherited role as an extra
      # MemberRole row on the author's own membership, next to the direct rows.
      group = Group.find(10)
      group.user_ids += [ User.find(2).id ]
      Member.create!(user_id: group.id, project_id: @issue.project_id, role_ids: [ 2 ])

      data = @test_class.generate_issue_data_with_roles(@issue)

      assert_equal %w[Developer Manager], data[:author][:roles]
    end

    should "include roles inherited through group membership" do
      Member.create!(user_id: 10, project_id: @issue.project_id, role_ids: [ 3 ])
      Journal.create!(journalized: @issue, user: User.find(8), notes: "note from group member")

      data = @test_class.generate_issue_data_with_roles(@issue)
      journal_user = data[:journals].find { |j| j[:user] && j[:user][:id] == 8 }

      assert_equal %w[Reporter], journal_user[:user][:roles]
    end

    should "return empty roles for a non-member user" do
      Journal.create!(journalized: @issue, user: User.find(9), notes: "note from non member")

      data = @test_class.generate_issue_data_with_roles(@issue)
      journal_user = data[:journals].find { |j| j[:user] && j[:user][:id] == 9 }

      assert_equal [], journal_user[:user][:roles]
      assert_not_includes journal_user[:user][:roles], "Non member"
    end

    should "return empty roles for an anonymous user" do
      Journal.create!(journalized: @issue, user: User.find(6), notes: "note from anonymous")

      data = @test_class.generate_issue_data_with_roles(@issue)
      journal_user = data[:journals].find { |j| j[:user] && j[:user][:id] == 6 }

      assert_equal [], journal_user[:user][:roles]
      assert_not_includes journal_user[:user][:roles], "Anonymous"
    end

    should "keep assigned_to nil without a roles key when the assignee is removed" do
      @issue.update!(assigned_to_id: 2)
      @issue.update!(assigned_to_id: nil)

      data = @test_class.generate_issue_data_with_roles(@issue)

      assert_nil data[:assigned_to]
    end

    should "return the roles of a Group assigned to the issue in the same shape as a User" do
      Member.create!(user_id: 10, project_id: @issue.project_id, role_ids: [ 3 ])
      @issue.assigned_to = Group.find(10)

      data = @test_class.generate_issue_data_with_roles(@issue)

      assert_equal({ id: 10, name: "A Team", roles: %w[Reporter] }, data[:assigned_to])
    end

    should "return empty roles for a non-member Group assignee without raising" do
      @issue.assigned_to = Group.find(11)

      data = assert_nothing_raised do
        @test_class.generate_issue_data_with_roles(@issue)
      end

      assert_equal({ id: 11, name: "B Team", roles: [] }, data[:assigned_to])
    end

    should "not raise when the assignee is removed" do
      @issue.update!(assigned_to_id: 2)
      @issue.update!(assigned_to_id: nil)

      assert_nothing_raised do
        @test_class.generate_issue_data_with_roles(@issue)
      end
    end
  end

  context "generate_issue_data roles isolation" do
    setup do
      @issue = Issue.find(1)
      @issue.assigned_to = User.find(2)
      @test_class = TestClass.new
    end

    should "never include roles in the shared generate_issue_data output" do
      Member.create!(user_id: 10, project_id: @issue.project_id, role_ids: [ 3 ])
      Journal.create!(journalized: @issue, user: User.find(9), notes: "note from non member")
      Journal.create!(journalized: @issue, user: User.find(2), notes: "note from member")

      json = JSON.generate(@test_class.generate_issue_data(@issue))

      assert_not_includes json, "roles"
    end
  end

  context "WithRoles module boundary" do
    should "not expose role enrichment to classes that include only IssueJson" do
      plain_class = Class.new { include RedmineAiHelper::Util::IssueJson }
      enrichable_class = Class.new { include RedmineAiHelper::Util::IssueJson::WithRoles }

      assert_not plain_class.method_defined?(:generate_issue_data_with_roles),
        "generate_issue_data_with_roles must not be reachable without explicitly including WithRoles"
      assert enrichable_class.method_defined?(:generate_issue_data_with_roles)
    end
  end

  class TestClass < RedmineAiHelper::BaseTools
    # This class is used to test the IssueJson module
    # It includes the IssueJson module to access its methods
    include RedmineAiHelper::Util::IssueJson
    include RedmineAiHelper::Util::IssueJson::WithRoles
  end
end
