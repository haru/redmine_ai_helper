require File.expand_path("../../../test_helper", __FILE__)

class VersionWriteToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :versions,
           :custom_fields, :custom_values, :enabled_modules, :roles, :members, :member_roles,
           :attachments, :projects_trackers

  def setup
    @provider = RedmineAiHelper::Tools::VersionWriteTools.new
    @project = Project.find(1)
    EnabledModule.create!(project_id: 1, name: "ai_helper")
    Role.find(1).add_permission!(:view_ai_helper)
    Role.find(1).add_permission!(:manage_versions)
    @previous_user = User.current
    User.current = User.find(2)
  end

  def teardown
    User.current = @previous_user
  end

  context "create_version" do
    should "create a version with defaults and return the version hash" do
      assert_difference "Version.count", 1 do
        @result = @provider.create_version(project_id: 1, name: "2026-W42")
      end

      assert_equal "open", @result[:status]
      assert_equal "none", @result[:sharing]
      assert_equal "2026-W42", @result[:name]
      assert_equal({ id: 1, name: @project.name }, @result[:project])
      %i[id description due_date wiki_page_title custom_fields created_on updated_on url_for_version].each do |key|
        assert @result.key?(key), "expected key #{key}"
      end
      assert_equal "/versions/#{@result[:id]}", @result[:url_for_version]
      assert_not @result.key?(:estimated_hours)
      assert_not @result.key?(:spent_hours)
    end

    should "create a version with all attributes" do
      cf = create_version_custom_field
      result = @provider.create_version(
        project_id: 1, name: "Full", description: "desc", status: "locked", due_date: "2026-10-16",
        sharing: "descendants", wiki_page_title: "Wiki", custom_fields: [ { field_id: cf.id, value: "Release search" } ]
      )
      version = Version.find(result[:id])

      assert_equal "desc", version.description
      assert_equal "locked", version.status
      assert_equal Date.new(2026, 10, 16), version.effective_date
      assert_equal "descendants", version.sharing
      assert_equal "Wiki", version.wiki_page_title
      assert_equal "Release search", version.custom_field_value(cf)
      assert_includes result[:custom_fields], { id: cf.id, name: cf.name, value: "Release search" }
    end

    should "set the default project version" do
      result = @provider.create_version(project_id: 1, name: "Default", default_project_version: true)

      assert_equal result[:id], @project.reload.default_version_id
    end

    should "not unset the default project version when false is given" do
      current = Version.create!(project: @project, name: "Current")
      @project.update_column(:default_version_id, current.id)
      @provider.create_version(project_id: 1, name: "Other", default_project_version: false)

      assert_equal current.id, @project.reload.default_version_id
    end

    should "skip a custom field entry without field_id and set the others" do
      cf = create_version_custom_field
      result = @provider.create_version(
        project_id: 1, name: "Skip", custom_fields: [ { field_id: nil, value: "ignored" }, { field_id: cf.id, value: "kept" } ]
      )

      assert_nil result[:error]
      assert_equal "kept", Version.find(result[:id]).custom_field_value(cf)
    end

    should "return permission denied without manage_versions" do
      Role.find(1).remove_permission!(:manage_versions)

      assert_no_difference "Version.count" do
        assert_equal({ error: "Permission denied" }, @provider.create_version(project_id: 1, name: "X"))
      end
    end

    should "return errors for inaccessible or missing projects and missing arguments" do
      assert_no_difference "Version.count" do
        assert_equal({ error: "Project is not accessible: id = 2" }, @provider.create_version(project_id: 2, name: "X"))
        assert_equal({ error: "Project not found. id = 999" }, @provider.create_version(project_id: 999, name: "X"))
        assert_equal({ error: "project_id is required" }, @provider.create_version(project_id: nil, name: "X"))
        assert_equal({ error: "name is required" }, @provider.create_version(project_id: 1, name: nil))
      end
    end

    should "return a validation error for a duplicate name" do
      assert_no_difference "Version.count" do
        result = @provider.create_version(project_id: 1, name: "0.1")

        assert_includes result[:error], "Failed to create version: Name has already been taken"
      end
    end

    should "continue after a failed call (one at a time)" do
      names = [ "0.1", "A", "B", "C" ]
      results = nil
      assert_difference "Version.count", 3 do
        results = names.map { |n| @provider.create_version(project_id: 1, name: n) }
      end

      assert results.first.key?(:error)
      assert(results.drop(1).none? { |r| r.key?(:error) })
    end

    should "reject a sharing the user is not allowed to set" do
      assert_no_difference "Version.count" do
        result = @provider.create_version(project_id: 1, name: "S", sharing: "system")

        assert result[:error].start_with?("Sharing 'system' is not allowed. Allowed values: ")
      end
    end

    should "reject custom fields that are not editable for versions" do
      editable = create_version_custom_field(name: "Editable")
      hidden = create_version_custom_field(name: "Hidden", visible: false, role_ids: [ 2 ])
      issue_cf = IssueCustomField.first
      [ 99999, hidden.id, issue_cf.id ].each do |field_id|
        assert_no_difference "Version.count" do
          result = @provider.create_version(project_id: 1, name: "CF", custom_fields: [ { field_id: field_id, value: "v" } ])

          assert_includes result[:error], "Custom field not editable for versions: #{field_id}. Editable custom fields: "
          assert_includes result[:error], "#{editable.id} (Editable)"
        end
      end
    end

    should "return a validation error for invalid attribute values" do
      [ { name: "n" * 61 }, { name: "Ok", description: "d" * 256 }, { name: "Ok", status: "invalid" },
        { name: "Ok", due_date: "not-a-date" } ].each do |attrs|
        assert_no_difference "Version.count" do
          result = @provider.create_version(project_id: 1, **attrs)

          assert result[:error].start_with?("Failed to create version: "), result.inspect
        end
      end
    end

    should "raise system failures instead of returning an error" do
      Version.any_instance.stubs(:save).raises(ActiveRecord::StatementInvalid)

      assert_raises(ActiveRecord::StatementInvalid) do
        @provider.create_version(project_id: 1, name: "Boom")
      end
    end
  end

  context "update_version" do
    setup do
      @version = Version.create!(project: @project, name: "Upd", description: "orig", status: "open",
                                 effective_date: Date.new(2026, 1, 1), sharing: "none", wiki_page_title: "Orig")
    end

    should "change only the given attributes" do
      result = @provider.update_version(version_id: @version.id, status: "closed")
      @version.reload

      assert_equal "closed", @version.status
      assert_equal "Upd", @version.name
      assert_equal "orig", @version.description
      assert_equal Date.new(2026, 1, 1), @version.effective_date
      assert_equal "none", @version.sharing
      assert_equal "Orig", @version.wiki_page_title
      assert_equal "closed", result[:status]
      assert_equal "/versions/#{@version.id}", result[:url_for_version]
    end

    should "update several attributes including custom fields and default version" do
      cf = create_version_custom_field
      result = @provider.update_version(
        version_id: @version.id, name: "Renamed", description: "new", due_date: "2026-12-31", sharing: "descendants",
        wiki_page_title: "New", custom_fields: [ { field_id: cf.id, value: "goal" } ], default_project_version: true
      )
      @version.reload

      assert_equal "Renamed", @version.name
      assert_equal "new", @version.description
      assert_equal Date.new(2026, 12, 31), @version.effective_date
      assert_equal "descendants", @version.sharing
      assert_equal "New", @version.wiki_page_title
      assert_equal "goal", @version.custom_field_value(cf)
      assert_equal @version.id, @project.reload.default_version_id
      assert_equal "Renamed", result[:name]
    end

    should "clear attributes with empty strings" do
      @provider.update_version(version_id: @version.id, due_date: "", description: "", wiki_page_title: "")
      @version.reload

      assert_nil @version.effective_date
      assert_equal "", @version.description.to_s
      assert_equal "", @version.wiki_page_title.to_s
    end

    should "return permission denied without manage_versions" do
      Role.find(1).remove_permission!(:manage_versions)

      assert_equal({ error: "Permission denied" }, @provider.update_version(version_id: @version.id, status: "closed"))
      assert_equal "open", @version.reload.status
    end

    should "return not found for missing, invisible, or nil version ids" do
      assert_equal({ error: "Version not found. id = 999" }, @provider.update_version(version_id: 999, status: "closed"))
      assert_equal({ error: "version_id is required" }, @provider.update_version(version_id: nil, status: "closed"))
      hidden_project = Project.create!(name: "Hidden", identifier: "hidden-proj", is_public: false)
      hidden = Version.create!(project: hidden_project, name: "Hidden version")
      assert_equal({ error: "Version not found. id = #{hidden.id}" }, @provider.update_version(version_id: hidden.id, status: "closed"))
    end

    should "check permission on the owning project of a shared version" do
      # Version 7 is shared system-wide but belongs to project 2 where ai_helper is not enabled.
      result = @provider.update_version(version_id: 7, status: "closed")

      assert_equal({ error: "Project is not accessible: id = 2" }, result)
      assert_equal "open", Version.find(7).status
    end

    should "reject a new sharing the user may not set but allow keeping the current one" do
      result = @provider.update_version(version_id: @version.id, sharing: "system")

      assert result[:error].start_with?("Sharing 'system' is not allowed. Allowed values: ")
      assert_equal "none", @version.reload.sharing

      @version.update_column(:sharing, "system")
      result = @provider.update_version(version_id: @version.id, sharing: "system", description: "kept")

      assert_nil result[:error]
      assert_equal "kept", @version.reload.description
    end

    should "reject custom fields that are not editable" do
      create_version_custom_field(name: "Editable")
      result = @provider.update_version(version_id: @version.id, custom_fields: [ { field_id: 99999, value: "x" } ])

      assert_includes result[:error], "Custom field not editable for versions: 99999. Editable custom fields: "
    end

    should "not save and return the current values when nothing is given" do
      updated_on = @version.reload.updated_on
      result = @provider.update_version(version_id: @version.id)

      assert_equal updated_on, @version.reload.updated_on
      assert_equal "Upd", result[:name]
    end

    should "return a validation error for a duplicate name" do
      result = @provider.update_version(version_id: @version.id, name: "0.1")

      assert_includes result[:error], "Failed to update version: Name has already been taken"
    end

    should "reopen a closed version" do
      @version.update!(status: "closed")
      result = @provider.update_version(version_id: @version.id, status: "open")

      assert_equal "open", result[:status]
    end

    should "raise system failures instead of returning an error" do
      Version.any_instance.stubs(:save).raises(ActiveRecord::StatementInvalid)

      assert_raises(ActiveRecord::StatementInvalid) do
        @provider.update_version(version_id: @version.id, status: "closed")
      end
    end
  end

  context "delete_version" do
    setup do
      @version = Version.create!(project: @project, name: "Del")
    end

    should "delete an unused version" do
      result = @provider.delete_version(version_id: @version.id)

      assert_equal({ deleted: true, id: @version.id, name: "Del" }, result)
      assert_nil Version.find_by(id: @version.id)
    end

    should "refuse to delete a version with assigned issues" do
      issue = Issue.find(1)
      issue.update_column(:fixed_version_id, @version.id)
      result = @provider.delete_version(version_id: @version.id)

      assert_equal({ error: "Version is in use and cannot be deleted: 1 issue(s) are assigned to it" }, result)
      assert Version.exists?(@version.id)
    end

    should "refuse to delete a version with attachments" do
      Attachment.create!(container: @version, file: uploaded_test_file("testfile.txt", "text/plain"), author: User.find(2))
      result = @provider.delete_version(version_id: @version.id)

      assert_equal({ error: "Version is in use and cannot be deleted: it has attachments" }, result)
      assert Version.exists?(@version.id)
    end

    should "refuse to delete a version referenced by a version custom field" do
      cf = IssueCustomField.create!(name: "Target", field_format: "version", is_for_all: true, tracker_ids: [ 1 ])
      CustomValue.create!(customized: Issue.find(1), custom_field: cf, value: @version.id.to_s)
      result = @provider.delete_version(version_id: @version.id)

      assert_equal({ error: "Version is in use and cannot be deleted: it is referenced by a version custom field" }, result)
      assert Version.exists?(@version.id)
    end

    should "clear the project's default version when deleted" do
      @project.update_column(:default_version_id, @version.id)
      @provider.delete_version(version_id: @version.id)

      assert_nil @project.reload.default_version_id
    end

    should "return errors for permission, missing and nil ids" do
      assert_equal({ error: "Version not found. id = 999" }, @provider.delete_version(version_id: 999))
      assert_equal({ error: "version_id is required" }, @provider.delete_version(version_id: nil))
      Role.find(1).remove_permission!(:manage_versions)
      assert_equal({ error: "Permission denied" }, @provider.delete_version(version_id: @version.id))
      assert Version.exists?(@version.id)
    end
  end

  private

  # Create a version custom field.
  def create_version_custom_field(**attrs)
    VersionCustomField.create!({ name: "Sprint goal", field_format: "string", visible: true, editable: true }.merge(attrs))
  end
end
