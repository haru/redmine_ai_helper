# frozen_string_literal: true

require_relative "../test_helper"
require "redmine_ai_helper/agents/issue_read_agent"
require "redmine_ai_helper/agents/wiki_agent"
require "redmine_ai_helper/agents/project_agent"
require "redmine_ai_helper/agents/mcp_agent"

# PromptTemplate#format rejects missing and unknown variables. These tests run
# the real templates through the callers that build their variables inline, so
# a caller/template mismatch fails here instead of being swallowed by the
# callers' broad rescue (inline completion rescues and returns "").
#
# The remaining callers already run their real templates in existing tests
# (they do not stub load_prompt/format): LeaderAgent generate_goal and
# generate_steps (leader_agent_test), DocumentationAgent#check_typos
# (documentation_agent_test), IssueContentAnalyzer (issue_content_analyzer_test),
# SystemPrompt (system_prompt_test), BaseAgent system prompt (base_agent_test),
# FileTools (file_tools_test) and AttachmentFileHelper
# (attachment_file_helper_test). Callers that existing tests exercise only with
# a stubbed load_prompt (wiki_summary, issue_summary, generate_issue_reply,
# suggest_stuff_todo, the backstories) and the leader's web search notice are
# driven with the real templates below.
class PromptTemplateCallersTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :issue_statuses, :trackers, :enumerations, :wikis, :wiki_pages, :wiki_contents, :versions, :issue_categories, :custom_fields, :enabled_modules

  setup do
    @project = Project.find(1)
    @project.enable_module!(:ai_helper)
    @previous_user = User.current
    User.current = User.find(1)
  end

  teardown do
    User.current = @previous_user
  end

  context "IssueReadAgent inline completion" do
    setup do
      @agent = RedmineAiHelper::Agents::IssueReadAgent.new(project: @project)
    end

    %w[en ja].each do |locale|
      { "description" => "issue_read_agent/inline_completion", "note" => "issue_read_agent/note_inline_completion" }.each do |context_type, template_name|
        should "build exactly the variables declared by #{template_name} (#{locale})" do
          I18n.with_locale(locale.to_sym) do
            declared = RedmineAiHelper::Util::PromptLoader.load_template(template_name).input_variables
            vars = @agent.build_completion_template_vars({}, context_type, "pre", "suf", 3)

            assert_equal declared.sort, vars.keys.map(&:to_s).sort
          end
        end

        should "reach the LLM when completing a #{context_type} (#{locale}) with the real template" do
          I18n.with_locale(locale.to_sym) do
            @agent.expects(:chat).once.returns("completion")

            @agent.generate_text_completion(text: "abc", cursor_position: 1, context_type: context_type, project: @project)
          end
        end
      end
    end
  end

  context "WikiAgent inline completion" do
    setup do
      @agent = RedmineAiHelper::Agents::WikiAgent.new(project: @project)
      @wiki_page = WikiPage.find(1)
    end

    %w[en ja].each do |locale|
      [ false, true ].each do |section_edit|
        should "reach the LLM with the real template (#{locale}, section_edit=#{section_edit})" do
          I18n.with_locale(locale.to_sym) do
            @agent.expects(:chat).once.returns("completion")

            @agent.generate_wiki_completion(text: "abc", cursor_position: 1, project: @project,
                                            wiki_page: @wiki_page, is_section_edit: section_edit)
          end
        end
      end
    end
  end

  context "ProjectAgent" do
    setup do
      @agent = RedmineAiHelper::Agents::ProjectAgent.new(project: @project, langfuse: RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: "test"))
    end

    %w[en ja].each do |locale|
      should "format its backstory with the real template (#{locale})" do
        I18n.with_locale(locale.to_sym) do
          assert_kind_of String, @agent.backstory
        end
      end

      [ true, false ].each do |with_versions|
        should "format every health report template with the real templates (#{locale}, open versions=#{with_versions})" do
          I18n.with_locale(locale.to_sym) do
            mock_tools = mock("ProjectTools")
            mock_tools.stubs(:get_metrics).returns({ issue_statistics: { total_issues: 3 } })
            RedmineAiHelper::Tools::ProjectTools.stubs(:new).returns(mock_tools)
            calculator = mock("ProjectMetricsCalculator")
            calculator.stubs(:calculate_repository_metrics).returns({ repository_available: false })
            RedmineAiHelper::ProjectMetricsCalculator.stubs(:new).returns(calculator)
            versions = with_versions ? Version.where(project_id: @project.id) : Version.none
            @project.stubs(:shared_versions).returns(versions)
            captured = nil
            @agent.expects(:think_chat).with { |messages, *| captured = messages.first[:content] }.returns("report")

            @agent.project_health_report(project: @project)

            assert_not_nil captured
          end
        end
      end

      should "format the health report comparison with the real template (#{locale})" do
        I18n.with_locale(locale.to_sym) do
          old_report = stub(project_id: 1, project: @project, created_at: 2.days.ago, health_report: "old", metrics: "{}")
          new_report = stub(project_id: 1, project: @project, created_at: 1.day.ago, health_report: "new", metrics: "{}")
          @agent.expects(:think_chat).returns("comparison")

          assert_equal "comparison", @agent.health_report_comparison(old_report: old_report, new_report: new_report)
        end
      end
    end
  end

  context "callers that existing tests exercise with a stubbed prompt" do
    %w[en ja].each do |locale|
      should "format WikiAgent#wiki_summary with the real template (#{locale})" do
        I18n.with_locale(locale.to_sym) do
          agent = RedmineAiHelper::Agents::WikiAgent.new(project: @project)
          agent.expects(:chat).once.returns("summary")

          assert_equal "summary", agent.wiki_summary(wiki_page: WikiPage.find(1))
        end
      end

      [ nil, "Keep it short" ].each do |instructions|
        should "format IssueReadAgent#issue_summary with the real templates (#{locale}, instructions=#{instructions.inspect})" do
          I18n.with_locale(locale.to_sym) do
            AiHelperProjectSetting.settings(@project).update!(issue_summary_instructions: instructions)
            agent = RedmineAiHelper::Agents::IssueReadAgent.new(project: @project)
            captured = nil
            agent.expects(:chat).with { |messages, *| captured = messages.first[:content] }.returns("summary")

            agent.issue_summary(issue: Issue.find(1))

            assert_not_nil captured
            assert_equal instructions.present?, captured.include?("Keep it short")
          end
        end
      end

      should "format IssueReadAgent#generate_issue_reply with the real template (#{locale})" do
        I18n.with_locale(locale.to_sym) do
          agent = RedmineAiHelper::Agents::IssueReadAgent.new(project: @project)
          agent.expects(:think_chat).once.returns("reply")

          assert_equal "reply", agent.generate_issue_reply(issue: Issue.find(1), instructions: "be polite")
        end
      end

      should "format IssueReadAgent#suggest_stuff_todo with the real template (#{locale})" do
        I18n.with_locale(locale.to_sym) do
          agent = RedmineAiHelper::Agents::IssueReadAgent.new(project: @project)
          agent.expects(:chat).once.returns("todo")

          assert_equal "todo", agent.suggest_stuff_todo
        end
      end

      should "format the LeaderAgent web search notice with the real template (#{locale})" do
        I18n.with_locale(locale.to_sym) do
          RedmineAiHelper::Agents::WebSearchAgent.any_instance.stubs(:enabled?).returns(false)
          agent = RedmineAiHelper::Agents::LeaderAgent.new(project: @project)

          assert_not_includes agent.system_prompt.fixed, "#<RedmineAiHelper::Util::PromptTemplate"
        end
      end

      %w[
        DocumentationAgent IssueWriteAgent SystemAgent BoardAgent WikiAgent IssueReadAgent
        UserAgent VersionAgent LeaderAgent FileAgent RepositoryAgent
      ].each do |agent_name|
        should "return the formatted backstory text from #{agent_name} (#{locale})" do
          I18n.with_locale(locale.to_sym) do
            agent = RedmineAiHelper::Agents.const_get(agent_name).new(project: @project)

            assert_instance_of String, agent.backstory
            assert_not_empty agent.backstory
          end
        end
      end
    end
  end

  context "MCP agents" do
    should "format the McpAgent backstory with the real template" do
      assert_kind_of String, RedmineAiHelper::Agents::McpAgent.new(project: @project).backstory
    end

    should "format the mcp_agent backstory for a named server as McpServerLoader does" do
      template = RedmineAiHelper::Util::PromptLoader.load_template("mcp_agent/backstory")

      assert_includes template.format(server_name: "srv"), "srv"
    end
  end
end
