# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)
require_relative "no_delete_tools_assertions"

class MemberToolsTest < ActiveSupport::TestCase
  include NoDeleteToolsAssertions

  fixtures :projects, :enabled_modules, :users, :members, :member_roles, :roles, :groups_users

  setup do
    @provider = RedmineAiHelper::Tools::MemberTools.new
    @project = Project.find(1)
    EnabledModule.create!(project_id: @project.id, name: "ai_helper") unless @project.module_enabled?(:ai_helper)
    Role.find(1).add_permission!(:view_ai_helper)
    Role.find(2).add_permission!(:view_ai_helper)
    # Give jsmith (member 1) the Developer role as well so his manageable roles
    # are Manager + Developer; Reporter (role 3) stays unmanageable for him.
    Member.find(1).update!(role_ids: [ 1, 2 ])
    @previous_user = User.current
    User.current = User.find(2) # jsmith: Manager in project 1
  end

  teardown do
    User.current = @previous_user
  end

  def member_counts
    { members: Member.count, member_roles: MemberRole.count }
  end

  def setup_project5_access
    @project5 = Project.find(5)
    EnabledModule.create!(project_id: @project5.id, name: "ai_helper") unless @project5.module_enabled?(:ai_helper)
  end

  # Restrict jsmith's manageable roles to Manager + Developer by turning off
  # all_roles_managed (Redmine 7 lets a role manage all givable roles by default).
  def restrict_manageable_roles
    Role.find(1).update!(all_roles_managed: false, managed_role_ids: [ 1, 2 ])
    Role.find(2).update!(all_roles_managed: false, managed_role_ids: [ 1, 2 ])
  end

  context "tool name length" do
    should "keep every generated tool name within 64 characters" do
      RedmineAiHelper::Tools::MemberTools.tool_classes.each do |tool_class|
        assert_operator tool_class.new.name.length, :<=, 64,
          "#{tool_class.name} exceeds the 64 character tool name limit: #{tool_class.new.name}"
      end
    end
  end

  context "find_member_candidates" do
    should "raise permission denied without manage_members" do
      Role.find(1).remove_permission!(:manage_members)
      Role.find(2).remove_permission!(:manage_members)

      result = @provider.find_member_candidates(project_id: @project.id, query: "misc")

      assert_equal({ error: "Permission denied: manage_members on project #{@project.id}" }, result)
    end

    should "exclude members and locked users" do
      # dlopper (user 3) is a member of project 1 and dlopper2 (user 5) is locked;
      # neither may appear in the candidates.
      result = @provider.find_member_candidates(project_id: @project.id, query: "dlopper")

      assert_equal({ candidates: [], truncated: false }, result)
    end

    should "find active visible users by login" do
      result = @provider.find_member_candidates(project_id: @project.id, query: "misc")

      ids = result[:candidates].map { |c| c[:id] }
      assert_equal [ 8, 9 ], ids.sort
      assert_equal false, result[:truncated]
      result[:candidates].each do |candidate|
        assert_equal "user", candidate[:type]
        assert candidate[:login].present?
        assert candidate[:name].present?
      end
    end

    should "find groups with nil login" do
      result = @provider.find_member_candidates(project_id: @project.id, query: "team")

      ids = result[:candidates].map { |c| c[:id] }
      assert_equal [ 10, 11 ], ids.sort
      result[:candidates].each do |candidate|
        assert_equal "group", candidate[:type]
        assert_nil candidate[:login]
      end
    end

    should "truncate at 100 candidates" do
      101.times do |i|
        User.create!(
          login: "trunc#{i}", firstname: "Trunc", lastname: "Ation#{i}",
          mail: "trunc#{i}@example.com", password: "aBcDeF12", password_confirmation: "aBcDeF12"
        )
      end

      result = @provider.find_member_candidates(project_id: @project.id, query: "Trunc")

      assert_equal 100, result[:candidates].size
      assert_equal true, result[:truncated]
    end
  end

  context "add_member" do
    should "add a user with one role and return the Member shape with project" do
      assert_difference "Member.count", 1 do
        assert_difference "MemberRole.count", 1 do
          @result = @provider.add_member(project_id: @project.id, principal_id: 8, role_ids: [ 2 ])
        end
      end

      member = Member.find(@result[:member_id])
      assert_equal 8, member.user_id
      assert_equal [ 2 ], member.role_ids
      assert_equal 8, @result[:user_id]
      assert_equal "miscuser8", @result[:login]
      assert_equal "user", @result[:type]
      assert_equal "active", @result[:status]
      assert_equal [ { id: 2, name: "Developer", inherited: false, inherited_from: nil, editable: true } ], @result[:roles]
      assert_equal({ id: @project.id, name: @project.name }, @result[:project])
    end

    should "add a group as a member" do
      # Redmine creates a membership for each of the group's users along with the
      # group's own one, so both counts grow by 2 (group A Team has 1 user).
      assert_difference "Member.count", 2 do
        assert_difference "MemberRole.count", 2 do
          @result = @provider.add_member(project_id: @project.id, principal_id: 10, role_ids: [ 1 ])
        end
      end

      assert_equal 10, @result[:user_id]
      assert_equal "group", @result[:type]
      assert_nil @result[:login]
      assert_equal "A Team", @result[:user_name]
    end

    should "raise permission denied and change nothing" do
      Role.find(1).remove_permission!(:manage_members)
      Role.find(2).remove_permission!(:manage_members)
      before = member_counts

      result = @provider.add_member(project_id: @project.id, principal_id: 8, role_ids: [ 1 ])

      assert_equal({ error: "Permission denied: manage_members on project #{@project.id}" }, result)
      assert_equal before, member_counts
    end

    should "raise when role_ids is empty and change nothing" do
      before = member_counts

      result = @provider.add_member(project_id: @project.id, principal_id: 8, role_ids: [])

      assert result[:error].present?
      assert_equal before, member_counts
    end

    should "reject a role the caller cannot manage" do
      restrict_manageable_roles
      before = member_counts

      result = @provider.add_member(project_id: @project.id, principal_id: 8, role_ids: [ 3 ])

      assert_equal({ error: "Roles you cannot manage: 3 (Reporter)" }, result)
      assert_equal before, member_counts
    end

    should "grant nothing when one role among valid ones is unmanageable" do
      restrict_manageable_roles
      before = member_counts

      result = @provider.add_member(project_id: @project.id, principal_id: 8, role_ids: [ 2, 3 ])

      assert_equal({ error: "Roles you cannot manage: 3 (Reporter)" }, result)
      assert_equal before, member_counts
    end

    should "reject a nonexistent role" do
      before = member_counts

      result = @provider.add_member(project_id: @project.id, principal_id: 8, role_ids: [ 999 ])

      assert result[:error].present?
      assert_equal before, member_counts
    end

    should "reject a locked, invisible, or nonexistent principal" do
      before = member_counts

      result = @provider.add_member(project_id: @project.id, principal_id: 5, role_ids: [ 1 ])

      assert_equal({ error: "Principal cannot be added: id = 5 (locked, not visible, or not found)" }, result)
      assert_equal before, member_counts

      result = @provider.add_member(project_id: @project.id, principal_id: 999, role_ids: [ 1 ])

      assert_equal({ error: "Principal cannot be added: id = 999 (locked, not visible, or not found)" }, result)
      assert_equal before, member_counts
    end

    should "not duplicate a member and report the current roles" do
      # user 3 (dlopper) is already a member of project 1 with the Developer role
      before = member_counts

      result = @provider.add_member(project_id: @project.id, principal_id: 3, role_ids: [ 1 ])

      assert_equal({ error: "Already a member: id = 3, roles: Developer" }, result)
      assert_equal before, member_counts
    end

    should "reject a closed project" do
      project = Project.create!(
        name: "Closed Member Test", identifier: "closed-member-test",
        is_public: true, status: Project::STATUS_CLOSED
      )
      # The closed project has no ai_helper module; with the scope on it stays
      # accessible, so only the closed guard can reject this call.
      AiHelperSetting.stubs(:all_projects_scope?).returns(true)
      before = member_counts

      result = @provider.add_member(project_id: project.id, principal_id: 8, role_ids: [ 1 ])

      assert_equal({ error: "Project is closed: id = #{project.id}" }, result)
      assert_equal before, member_counts
    end

    should "reject a project that is not accessible via AI Helper" do
      AiHelperSetting.stubs(:all_projects_scope?).returns(false)
      project = Project.create!(name: "No Module Test", identifier: "no-module-test", is_public: true)
      before = member_counts

      result = @provider.add_member(project_id: project.id, principal_id: 8, role_ids: [ 1 ])

      assert_equal({ error: "Project is not accessible: id = #{project.id}" }, result)
      assert_equal before, member_counts
    end
  end

  context "update_member_roles" do
    should "replace the direct roles when both add and remove are given" do
      # member 2: user 3 in project 1, direct role Developer (2)
      assert_no_difference "Member.count" do
        @result = @provider.update_member_roles(project_id: @project.id, principal_id: 3, add_role_ids: [ 1 ], remove_role_ids: [ 2 ])
      end

      member = Member.find(@result[:member_id])
      assert_equal [ 1 ], member.member_roles.select { |mr| mr.inherited_from.nil? }.map(&:role_id)
      assert_equal [ 1 ], member.role_ids.sort
      assert_equal [ 3 ], [ @result[:user_id] ]
      assert_equal({ id: @project.id, name: @project.name }, @result[:project])
      assert_equal [], @result[:unchanged_role_ids]
    end

    should "keep inherited roles and return unchanged ids" do
      setup_project5_access
      # member 7: user 8 in project 5, both roles inherited from group A Team
      result = @provider.update_member_roles(project_id: @project5.id, principal_id: 8, add_role_ids: [ 1 ])

      assert_equal [ 1 ], result[:unchanged_role_ids]
      member = Member.find(result[:member_id])
      assert_equal [ 1, 2 ], member.role_ids.sort
      assert member.member_roles.all? { |mr| mr.inherited_from.present? },
        "inherited roles must be kept, got: #{member.member_roles.inspect}"
    end

    should "change only the direct roles of a member with both direct and inherited roles" do
      setup_project5_access
      member = Member.find(7) # user 8 in project 5, roles 1+2 inherited
      member.member_roles << MemberRole.new(role_id: 3)
      assert(member.reload.member_roles.any? { |mr| mr.role_id == 3 && mr.inherited_from.nil? })

      result = @provider.update_member_roles(project_id: @project5.id, principal_id: 8, remove_role_ids: [ 3 ])

      assert_equal [], result[:unchanged_role_ids]
      member = Member.find(result[:member_id])
      assert_equal [ 1, 2 ], member.role_ids.sort
      assert member.member_roles.all? { |mr| mr.inherited_from.present? },
        "only the direct role must be removed, got: #{member.member_roles.inspect}"
    end

    should "report unchanged ids for an already held role and a role not held" do
      # user 3 holds role 2 only: adding 2 changes nothing, removing 1 changes nothing
      result = @provider.update_member_roles(project_id: @project.id, principal_id: 3, add_role_ids: [ 2 ], remove_role_ids: [ 1 ])

      assert_equal [ 1, 2 ], result[:unchanged_role_ids].sort
      member = Member.find(result[:member_id])
      assert_equal [ 2 ], member.role_ids.sort
    end

    should "raise for a principal that is not a member" do
      before = member_counts

      result = @provider.update_member_roles(project_id: @project.id, principal_id: 7, add_role_ids: [ 1 ])

      assert_equal({ error: "Not a member: principal id = 7" }, result)
      assert_equal before, member_counts
    end

    should "raise when both lists are empty" do
      result = @provider.update_member_roles(project_id: @project.id, principal_id: 3, add_role_ids: [], remove_role_ids: [])

      assert result[:error].present?
    end

    should "raise when the same role is added and removed" do
      result = @provider.update_member_roles(project_id: @project.id, principal_id: 3, add_role_ids: [ 1 ], remove_role_ids: [ 1 ])

      assert result[:error].present?
    end

    should "raise when granting or revoking a role the caller cannot manage" do
      restrict_manageable_roles

      result = @provider.update_member_roles(project_id: @project.id, principal_id: 3, add_role_ids: [ 3 ])

      assert_equal({ error: "Roles you cannot manage: 3 (Reporter)" }, result)

      # member 2 (user 3) has role 2; with restricted management role 2 is still
      # manageable, so grant Reporter first via a direct fixture update
      Member.find(2).member_roles << MemberRole.new(role_id: 3)
      result = @provider.update_member_roles(project_id: @project.id, principal_id: 3, remove_role_ids: [ 3 ])

      assert_equal({ error: "Roles you cannot manage: 3 (Reporter)" }, result)
    end

    should "raise when removing an inherited role" do
      setup_project5_access

      result = @provider.update_member_roles(project_id: @project5.id, principal_id: 8, remove_role_ids: [ 2 ])

      assert_equal({ error: "Inherited roles cannot be changed: 2 (Developer)" }, result)
      assert_equal [ 1, 2 ], Member.find(7).role_ids.sort
    end

    should "raise when the change would leave no role" do
      # member 2 (user 3) holds only role 2
      result = @provider.update_member_roles(project_id: @project.id, principal_id: 3, remove_role_ids: [ 2 ])

      assert_equal(
        { error: "A member must keep at least one role; use remove_member to remove the member" },
        result
      )
      assert_equal [ 2 ], Member.find(2).role_ids.sort
    end

    should "raise without manage_members permission and change nothing" do
      Role.find(1).remove_permission!(:manage_members)
      Role.find(2).remove_permission!(:manage_members)
      before = member_counts

      result = @provider.update_member_roles(project_id: @project.id, principal_id: 3, add_role_ids: [ 1 ])

      assert_equal({ error: "Permission denied: manage_members on project #{@project.id}" }, result)
      assert_equal before, member_counts
    end
  end

  context "remove_member" do
    should "remove the member and its member roles only, and clear category and default assignees" do
      setup_project5_access
      # Use user 3 (member 2 of project 1) as category and default assignee
      @project.update!(default_assigned_to_id: 3)
      category = IssueCategory.find(2)
      category.update!(assigned_to_id: 3)
      counts_before = {
        users: User.count, roles: Role.count, issues: Issue.count
      }
      member_roles_before = MemberRole.where(member_id: 2).count

      assert_difference "Member.count", -1 do
        assert_difference "MemberRole.count", -member_roles_before do
          @result = @provider.remove_member(project_id: @project.id, principal_id: 3)
        end
      end

      assert_equal true, @result[:removed]
      assert_equal @project.id, @result[:project_id]
      assert_equal({ id: 3, name: "Dave Lopper", login: "dlopper", type: "user" }, @result[:principal])
      assert_equal [ "Developer" ], @result[:roles]
      assert_nil Member.find_by(user_id: 3, project_id: @project.id)
      # User, Role, and Issue records are untouched
      assert_equal counts_before[:users], User.count
      assert_equal counts_before[:roles], Role.count
      assert_equal counts_before[:issues], Issue.count
      # The member is removed from category and project default assignees (Redmine behaviour)
      assert_nil category.reload.assigned_to_id
      assert_nil @project.reload.default_assigned_to_id
    end

    should "raise for a principal that is not a member" do
      result = @provider.remove_member(project_id: @project.id, principal_id: 7)

      assert_equal({ error: "Not a member: principal id = 7" }, result)
    end

    should "raise for a member with inherited roles" do
      setup_project5_access

      result = @provider.remove_member(project_id: @project5.id, principal_id: 8)

      assert_equal({ error: "Member has roles inherited from A Team" }, result)
      assert Member.find(7).present?
    end

    should "raise for a member with a role the caller cannot manage" do
      restrict_manageable_roles
      Member.find(2).member_roles << MemberRole.new(role_id: 3)

      result = @provider.remove_member(project_id: @project.id, principal_id: 3)

      assert_equal({ error: "Member has roles you cannot manage: Reporter" }, result)
      assert Member.find(2).present?
    end

    should "raise without manage_members permission and change nothing" do
      Role.find(1).remove_permission!(:manage_members)
      Role.find(2).remove_permission!(:manage_members)
      before = member_counts

      result = @provider.remove_member(project_id: @project.id, principal_id: 3)

      assert_equal({ error: "Permission denied: manage_members on project #{@project.id}" }, result)
      assert_equal before, member_counts
    end

    should "require confirmation in the tool description" do
      schema = RedmineAiHelper::Tools::MemberTools.function_schemas.to_openai_format
      description = schema.find { |f| f[:function][:name].end_with?("__remove_member") }[:function][:description]

      assert_match(/Always confirm with the user before/i, description)
    end
  end

  context "list_managed_roles" do
    should "raise permission denied without manage_members" do
      Role.find(1).remove_permission!(:manage_members)
      Role.find(2).remove_permission!(:manage_members)

      result = @provider.list_managed_roles(project_id: @project.id)

      assert_equal({ error: "Permission denied: manage_members on project #{@project.id}" }, result)
    end

    should "return only the roles the current user can manage" do
      result = @provider.list_managed_roles(project_id: @project.id)

      expected = User.current.managed_roles(@project).map { |role| { id: role.id, name: role.name } }
      assert_equal(expected.sort_by { |r| r[:id] }, result[:roles].sort_by { |r| r[:id] })
      # The fixtures give every givable role manage_members, so this must be non-empty
      assert result[:roles].any?
      # A role the user cannot manage (non-givable/builtin roles) never appears
      assert(result[:roles].none? { |r| r[:id] == Role.find(4).id })
    end
  end

  context "no destructive tools" do
    should "not define a delete, destroy, or archive tool" do
      assert_no_destructive_tool_names(RedmineAiHelper::Tools::MemberTools)
    end

    should "not call a destructive method in the tool code" do
      assert_destructive_calls_only(RedmineAiHelper::Tools::MemberTools, allowed: [ "member.destroy" ])
    end
  end
end
