require_relative "../test_helper"

class AiHelperCustomCommandTest < ActiveSupport::TestCase
  fixtures :users, :projects, :members, :member_roles, :roles

  def setup
    @user = User.find(2)
    @project = Project.find(1)
    @another_user = User.find(3)
  end

  context "name normalization" do
    should "convert name to lowercase on save" do
      command = AiHelperCustomCommand.create!(
        name: "Test-Command",
        prompt: "Test prompt",
        command_type: :global,
        user: @user
      )
      assert_equal "test-command", command.name
    end

    should "handle mixed case names" do
      command = AiHelperCustomCommand.create!(
        name: "MyCustomCommand",
        prompt: "Test prompt",
        command_type: :global,
        user: @user
      )
      assert_equal "mycustomcommand", command.name
    end
  end

  context "validations" do
    should "validate presence of name" do
      command = AiHelperCustomCommand.new(
        prompt: "Test prompt",
        command_type: :global,
        user: @user
      )
      assert_not command.valid?
      assert command.errors[:name].present?
    end

    should "validate presence of prompt" do
      command = AiHelperCustomCommand.new(
        name: "test",
        command_type: :global,
        user: @user
      )
      assert_not command.valid?
      assert command.errors[:prompt].present?
    end

    should "validate presence of command_type" do
      command = AiHelperCustomCommand.new(
        name: "test",
        prompt: "Test prompt",
        user: @user
      )
      command.command_type = nil
      assert_not command.valid?
      assert command.errors[:command_type].present?
    end

    should "validate format of name" do
      invalid_names = ["test space", "test@", "test!", "test#", "テスト"]
      invalid_names.each do |invalid_name|
        command = AiHelperCustomCommand.new(
          name: invalid_name,
          prompt: "Test prompt",
          command_type: :global,
          user: @user
        )
        assert_not command.valid?, "#{invalid_name} should be invalid"
        assert command.errors[:name].present?
      end
    end

    should "accept valid name formats" do
      valid_names = ["test", "test_command", "test-command", "Test123", "test_123-cmd"]
      valid_names.each do |valid_name|
        command = AiHelperCustomCommand.new(
          name: valid_name,
          prompt: "Test prompt",
          command_type: :global,
          user: @user
        )
        assert command.valid?, "#{valid_name} should be valid"
      end
    end

    should "validate length of name" do
      command = AiHelperCustomCommand.new(
        name: "a" * 51,
        prompt: "Test prompt",
        command_type: :global,
        user: @user
      )
      assert_not command.valid?
      assert command.errors[:name].present?
    end

    should "validate uniqueness of global commands" do
      AiHelperCustomCommand.create!(
        name: "global_test",
        prompt: "Test prompt",
        command_type: :global,
        user: @user
      )

      duplicate = AiHelperCustomCommand.new(
        name: "global_test",
        prompt: "Another prompt",
        command_type: :global,
        user: @another_user
      )
      assert_not duplicate.valid?
      assert duplicate.errors[:name].present?
    end

    should "validate uniqueness of project commands within project" do
      AiHelperCustomCommand.create!(
        name: "project_test",
        prompt: "Test prompt",
        command_type: :project,
        project: @project,
        user: @user
      )

      duplicate = AiHelperCustomCommand.new(
        name: "project_test",
        prompt: "Another prompt",
        command_type: :project,
        project: @project,
        user: @another_user
      )
      assert_not duplicate.valid?
      assert duplicate.errors[:name].present?
    end

    should "allow same name for project commands in different projects" do
      project2 = Project.find(2)

      AiHelperCustomCommand.create!(
        name: "project_test",
        prompt: "Test prompt",
        command_type: :project,
        project: @project,
        user: @user
      )

      command = AiHelperCustomCommand.new(
        name: "project_test",
        prompt: "Another prompt",
        command_type: :project,
        project: project2,
        user: @user
      )
      assert command.valid?
    end

    should "validate uniqueness of user commands for same user" do
      AiHelperCustomCommand.create!(
        name: "user_test",
        prompt: "Test prompt",
        command_type: :user,
        user_scope: :common,
        user: @user
      )

      duplicate = AiHelperCustomCommand.new(
        name: "user_test",
        prompt: "Another prompt",
        command_type: :user,
        user_scope: :common,
        user: @user
      )
      assert_not duplicate.valid?
      assert duplicate.errors[:name].present?
    end

    should "allow same name for user commands of different users" do
      AiHelperCustomCommand.create!(
        name: "user_test",
        prompt: "Test prompt",
        command_type: :user,
        user_scope: :common,
        user: @user
      )

      command = AiHelperCustomCommand.new(
        name: "user_test",
        prompt: "Another prompt",
        command_type: :user,
        user_scope: :common,
        user: @another_user
      )
      assert command.valid?
    end

    should "validate uniqueness of user project commands within user and project" do
      AiHelperCustomCommand.create!(
        name: "user_project_test",
        prompt: "Test prompt",
        command_type: :user,
        user_scope: :project_limited,
        project: @project,
        user: @user
      )

      duplicate = AiHelperCustomCommand.new(
        name: "user_project_test",
        prompt: "Another prompt",
        command_type: :user,
        user_scope: :project_limited,
        project: @project,
        user: @user
      )
      assert_not duplicate.valid?
      assert duplicate.errors[:name].present?
    end

    should "require project for project commands" do
      command = AiHelperCustomCommand.new(
        name: "test",
        prompt: "Test prompt",
        command_type: :project,
        user: @user
      )
      assert_not command.valid?
      assert command.errors[:project].present?
    end

    should "require project for user project_limited commands" do
      command = AiHelperCustomCommand.new(
        name: "test",
        prompt: "Test prompt",
        command_type: :user,
        user_scope: :project_limited,
        user: @user
      )
      assert_not command.valid?
      assert command.errors[:project].present?
    end

    should "not allow project for global commands" do
      command = AiHelperCustomCommand.new(
        name: "test",
        prompt: "Test prompt",
        command_type: :global,
        project: @project,
        user: @user
      )
      assert_not command.valid?
      assert command.errors[:project].present?
    end

    should "not allow project for user common commands" do
      command = AiHelperCustomCommand.new(
        name: "test",
        prompt: "Test prompt",
        command_type: :user,
        user_scope: :common,
        project: @project,
        user: @user
      )
      assert_not command.valid?
      assert command.errors[:project].present?
    end
  end

  context "scopes" do
    setup do
      @global_cmd = AiHelperCustomCommand.create!(
        name: "global",
        prompt: "Global prompt",
        command_type: :global,
        user: @user
      )

      @project_cmd = AiHelperCustomCommand.create!(
        name: "project",
        prompt: "Project prompt",
        command_type: :project,
        project: @project,
        user: @user
      )

      @user_common_cmd = AiHelperCustomCommand.create!(
        name: "user_common",
        prompt: "User common prompt",
        command_type: :user,
        user_scope: :common,
        user: @user
      )

      @user_project_cmd = AiHelperCustomCommand.create!(
        name: "user_project",
        prompt: "User project prompt",
        command_type: :user,
        user_scope: :project_limited,
        project: @project,
        user: @user
      )
    end

    should "return global commands" do
      commands = AiHelperCustomCommand.global_commands
      assert_includes commands, @global_cmd
      assert_not_includes commands, @project_cmd
      assert_not_includes commands, @user_common_cmd
      assert_not_includes commands, @user_project_cmd
    end

    should "return project commands for specific project" do
      commands = AiHelperCustomCommand.project_commands(@project.id)
      assert_not_includes commands, @global_cmd
      assert_includes commands, @project_cmd
      assert_not_includes commands, @user_common_cmd
      assert_not_includes commands, @user_project_cmd
    end

    should "return user common commands" do
      commands = AiHelperCustomCommand.user_common_commands(@user.id)
      assert_not_includes commands, @global_cmd
      assert_not_includes commands, @project_cmd
      assert_includes commands, @user_common_cmd
      assert_not_includes commands, @user_project_cmd
    end

    should "return user project commands" do
      commands = AiHelperCustomCommand.user_project_commands(@user.id, @project.id)
      assert_not_includes commands, @global_cmd
      assert_not_includes commands, @project_cmd
      assert_not_includes commands, @user_common_cmd
      assert_includes commands, @user_project_cmd
    end
  end

  context ".available_for" do
    setup do
      @global_cmd = AiHelperCustomCommand.create!(
        name: "global",
        prompt: "Global prompt",
        command_type: :global,
        user: @user
      )

      @project_cmd = AiHelperCustomCommand.create!(
        name: "project",
        prompt: "Project prompt",
        command_type: :project,
        project: @project,
        user: @user
      )

      @user_common_cmd = AiHelperCustomCommand.create!(
        name: "user_common",
        prompt: "User common prompt",
        command_type: :user,
        user_scope: :common,
        user: @user
      )

      @user_project_cmd = AiHelperCustomCommand.create!(
        name: "user_project",
        prompt: "User project prompt",
        command_type: :user,
        user_scope: :project_limited,
        project: @project,
        user: @user
      )
    end

    should "return all command types when project is specified" do
      commands = AiHelperCustomCommand.available_for(user: @user, project: @project)
      assert_includes commands, @global_cmd
      assert_includes commands, @project_cmd
      assert_includes commands, @user_common_cmd
      assert_includes commands, @user_project_cmd
    end

    should "return global and user common commands when project is nil" do
      commands = AiHelperCustomCommand.available_for(user: @user, project: nil)
      assert_includes commands, @global_cmd
      assert_not_includes commands, @project_cmd
      assert_includes commands, @user_common_cmd
      assert_not_includes commands, @user_project_cmd
    end

    should "not return other users commands" do
      commands = AiHelperCustomCommand.available_for(user: @another_user, project: @project)
      assert_includes commands, @global_cmd
      assert_includes commands, @project_cmd
      assert_not_includes commands, @user_common_cmd
      assert_not_includes commands, @user_project_cmd
    end
  end

  context ".find_command" do
    setup do
      @global_cmd = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Global prompt",
        command_type: :global,
        user: @user
      )
    end

    should "find global command by name" do
      command = AiHelperCustomCommand.find_command(name: "test", user: @user, project: nil)
      assert_equal @global_cmd, command
    end

    should "prioritize user command over project command" do
      project_cmd = AiHelperCustomCommand.create!(
        name: "priority",
        prompt: "Project prompt",
        command_type: :project,
        project: @project,
        user: @user
      )

      user_cmd = AiHelperCustomCommand.create!(
        name: "priority",
        prompt: "User prompt",
        command_type: :user,
        user_scope: :project_limited,
        project: @project,
        user: @user
      )

      command = AiHelperCustomCommand.find_command(name: "priority", user: @user, project: @project)
      assert_equal user_cmd, command
    end

    should "prioritize project command over global command" do
      global_cmd = AiHelperCustomCommand.create!(
        name: "priority",
        prompt: "Global prompt",
        command_type: :global,
        user: @user
      )

      project_cmd = AiHelperCustomCommand.create!(
        name: "priority",
        prompt: "Project prompt",
        command_type: :project,
        project: @project,
        user: @user
      )

      command = AiHelperCustomCommand.find_command(name: "priority", user: @user, project: @project)
      assert_equal project_cmd, command
    end

    should "find command regardless of input case" do
      command = AiHelperCustomCommand.find_command(name: "TEST", user: @user, project: nil)
      assert_equal @global_cmd, command

      command = AiHelperCustomCommand.find_command(name: "TeSt", user: @user, project: nil)
      assert_equal @global_cmd, command
    end

    should "return nil for non-existent command" do
      command = AiHelperCustomCommand.find_command(name: "nonexistent", user: @user, project: nil)
      assert_nil command
    end
  end

  context "#expand" do
    should "expand {input} variable" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Process this: {input}",
        command_type: :global,
        user: @user
      )

      result = command.expand(input: "some text", user: @user)
      assert_equal "Process this: some text", result
    end

    should "expand {project_name} variable" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Project: {project_name}",
        command_type: :project,
        project: @project,
        user: @user
      )

      result = command.expand(user: @user, project: @project)
      assert_equal "Project: #{@project.name}", result
    end

    should "expand {user_name} variable" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "User: {user_name}",
        command_type: :global,
        user: @user
      )

      result = command.expand(user: @user)
      assert_equal "User: #{@user.name}", result
    end

    should "expand {datetime} variable" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Date: {datetime}",
        command_type: :global,
        user: @user
      )

      datetime = Time.zone.parse("2026-02-01 12:00:00")
      result = command.expand(user: @user, datetime: datetime)
      assert_includes result, "2026-02-01"
    end

    should "expand multiple variables" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "User {user_name} in project {project_name}: {input}",
        command_type: :project,
        project: @project,
        user: @user
      )

      result = command.expand(input: "test data", user: @user, project: @project)
      assert_equal "User #{@user.name} in project #{@project.name}: test data", result
    end

    should "handle empty input" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Process: {input}",
        command_type: :global,
        user: @user
      )

      result = command.expand(user: @user)
      assert_equal "Process: ", result
    end

    should "handle missing project_name when project is nil" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Project: {project_name}",
        command_type: :global,
        user: @user
      )

      result = command.expand(user: @user, project: nil)
      assert_equal "Project: ", result
    end
  end

  context "#editable_by?" do
    should "allow creator to edit" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Test prompt",
        command_type: :global,
        user: @user
      )

      assert command.editable_by?(@user)
    end

    should "not allow other users to edit" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Test prompt",
        command_type: :global,
        user: @user
      )

      assert_not command.editable_by?(@another_user)
    end

    should "allow admin to edit" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Test prompt",
        command_type: :global,
        user: @user
      )

      admin = User.find(1)
      assert command.editable_by?(admin)
    end
  end

  context "#visible_to?" do
    should "be visible to all users for global commands" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Test prompt",
        command_type: :global,
        user: @user
      )

      assert command.visible_to?(@another_user)
    end

    should "be visible to project members for project commands" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Test prompt",
        command_type: :project,
        project: @project,
        user: @user
      )

      # Assuming @another_user is a member of @project
      # This might need adjustment based on fixtures
      assert command.visible_to?(@another_user, project: @project)
    end

    should "not be visible to other users for user commands" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Test prompt",
        command_type: :user,
        user_scope: :common,
        user: @user
      )

      assert_not command.visible_to?(@another_user)
    end

    should "be visible to the owner for user commands" do
      command = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Test prompt",
        command_type: :user,
        user_scope: :common,
        user: @user
      )

      assert command.visible_to?(@user)
    end
  end
end
