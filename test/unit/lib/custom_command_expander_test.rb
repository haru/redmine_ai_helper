require_relative "../../test_helper"

class CustomCommandExpanderTest < ActiveSupport::TestCase
  fixtures :users, :projects, :members, :member_roles, :roles

  def setup
    @user = User.find(2)
    @project = Project.find(1)
  end

  context "#command?" do
    should "return true for messages starting with /" do
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user)
      assert expander.command?("/test")
      assert expander.command?("/test with args")
      assert expander.command?("  /test")
    end

    should "return false for normal messages" do
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user)
      assert_not expander.command?("test")
      assert_not expander.command?("this is a /test")
      assert_not expander.command?("")
    end
  end

  context "#expand" do
    setup do
      @global_cmd = AiHelperCustomCommand.create!(
        name: "summarize",
        prompt: "Please summarize: {input}",
        command_type: :global,
        user: @user
      )

      @project_cmd = AiHelperCustomCommand.create!(
        name: "review",
        prompt: "Review for {project_name}: {input}",
        command_type: :project,
        project: @project,
        user: @user
      )
    end

    should "expand valid command" do
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: nil)
      result = expander.expand("/summarize test data")

      assert result[:expanded]
      assert_equal "Please summarize: test data", result[:message]
      assert_equal @global_cmd, result[:command]
    end

    should "expand command with project context" do
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: @project)
      result = expander.expand("/review security issues")

      assert result[:expanded]
      assert_includes result[:message], @project.name
      assert_includes result[:message], "security issues"
    end

    should "not expand unknown command" do
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: nil)
      result = expander.expand("/unknown test")

      assert_not result[:expanded]
      assert_equal "/unknown test", result[:message]
    end

    should "not expand non-command messages" do
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: nil)
      result = expander.expand("just a normal message")

      assert_not result[:expanded]
      assert_equal "just a normal message", result[:message]
    end

    should "handle command without arguments" do
      AiHelperCustomCommand.create!(
        name: "help",
        prompt: "Show help message",
        command_type: :global,
        user: @user
      )

      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: nil)
      result = expander.expand("/help")

      assert result[:expanded]
      assert_equal "Show help message", result[:message]
    end

    should "handle command with multiline arguments" do
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: nil)
      result = expander.expand("/summarize line1\nline2\nline3")

      assert result[:expanded]
      assert_includes result[:message], "line1\nline2\nline3"
    end

    should "be case insensitive for command name" do
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: nil)

      result = expander.expand("/SUMMARIZE test")
      assert result[:expanded]

      result = expander.expand("/Summarize test")
      assert result[:expanded]
    end

    should "respect command priority" do
      # Global command
      global = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Global: {input}",
        command_type: :global,
        user: @user
      )

      # Project command (higher priority)
      project_cmd = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "Project: {input}",
        command_type: :project,
        project: @project,
        user: @user
      )

      # User command (highest priority)
      user_cmd = AiHelperCustomCommand.create!(
        name: "test",
        prompt: "User: {input}",
        command_type: :user,
        user_scope: :project_limited,
        project: @project,
        user: @user
      )

      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: @project)
      result = expander.expand("/test data")

      assert result[:expanded]
      assert_equal "User: data", result[:message]
      assert_equal user_cmd, result[:command]
    end
  end

  context "#available_commands" do
    setup do
      @global_cmd = AiHelperCustomCommand.create!(
        name: "global_test",
        prompt: "Global prompt",
        command_type: :global,
        user: @user
      )

      @project_cmd = AiHelperCustomCommand.create!(
        name: "project_test",
        prompt: "Project prompt",
        command_type: :project,
        project: @project,
        user: @user
      )

      @user_cmd = AiHelperCustomCommand.create!(
        name: "user_test",
        prompt: "User prompt",
        command_type: :user,
        user_scope: :common,
        user: @user
      )
    end

    should "return all available commands" do
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: @project)
      commands = expander.available_commands

      assert commands.length >= 3
      command_names = commands.map { |c| c[:name] }
      assert_includes command_names, "global_test"
      assert_includes command_names, "project_test"
      assert_includes command_names, "user_test"
    end

    should "filter by prefix" do
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: @project)
      commands = expander.available_commands(prefix: "global")

      assert commands.length >= 1
      command_names = commands.map { |c| c[:name] }
      assert_includes command_names, "global_test"
      assert_not_includes command_names, "user_test"
    end

    should "be case insensitive for prefix" do
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: @project)
      commands = expander.available_commands(prefix: "GLOBAL")

      assert commands.length >= 1
      command_names = commands.map { |c| c[:name] }
      assert_includes command_names, "global_test"
    end

    should "return commands without project when project is nil" do
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: nil)
      commands = expander.available_commands

      command_names = commands.map { |c| c[:name] }
      assert_includes command_names, "global_test"
      assert_includes command_names, "user_test"
      assert_not_includes command_names, "project_test"
    end

    should "return command name and description" do
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: @project)
      commands = expander.available_commands(prefix: "global")

      command = commands.find { |c| c[:name] == "global_test" }
      assert command
      assert_equal "global_test", command[:name]
      assert_equal [:description, :name], command.keys.sort
    end

    should "return description when present" do
      @global_cmd.update!(description: "A test command")
      expander = RedmineAiHelper::CustomCommandExpander.new(user: @user, project: @project)
      commands = expander.available_commands(prefix: "global")

      command = commands.find { |c| c[:name] == "global_test" }
      assert_equal "A test command", command[:description]
    end
  end
end
