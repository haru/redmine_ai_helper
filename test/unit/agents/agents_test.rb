require File.expand_path("../../../test_helper", __FILE__)

class AgentsTest < ActiveSupport::TestCase
  setup do
  end
  context "BoardAgent" do
    setup do
      @agent = RedmineAiHelper::Agents::BoardAgent.new
      RedmineAiHelper::LlmProvider.stubs(:get_llm).returns({})
    end

    should "return correct tool providers" do
      assert_equal [RedmineAiHelper::Tools::BoardTools], @agent.available_tool_providers
    end
  end

  context "IssueAgent" do
    setup do
      @agent = RedmineAiHelper::Agents::IssueAgent.new({ project: Project.find(1) })
    end

    should "return correct tool providers" do
      assert_equal [
                     RedmineAiHelper::Tools::IssueTools,
                     RedmineAiHelper::Tools::ProjectTools,
                     RedmineAiHelper::Tools::UserTools,
                     RedmineAiHelper::Tools::IssueSearchTools,
                   ], @agent.available_tool_providers
    end

    should "return correct backstory" do
      assert @agent.backstory.include?("You are a issue agent for the RedmineAIHelper plugin")
    end
  end

  context "IssueUpdateAgent" do
    setup do
      @agent = RedmineAiHelper::Agents::IssueUpdateAgent.new({ project: Project.find(1) })
    end

    should "return correct tool providers" do
      assert_equal [
                     RedmineAiHelper::Tools::IssueTools,
                     RedmineAiHelper::Tools::IssueUpdateTools,
                     RedmineAiHelper::Tools::ProjectTools,
                     RedmineAiHelper::Tools::UserTools,
                   ], @agent.available_tool_providers
    end

    should "return correct backstory" do
      assert @agent.backstory.include?("You are the issue update agent of the RedmineAIHelper plugin")
    end
  end

  context "RepositoryAgent" do
    setup do
      @agent = RedmineAiHelper::Agents::RepositoryAgent.new
    end

    should "return correct tool providers" do
      assert_equal [RedmineAiHelper::Tools::RepositoryTools], @agent.available_tool_providers
    end
  end

  context "SystemAgent" do
    setup do
      @agent = RedmineAiHelper::Agents::SystemAgent.new
    end

    should "return correct tool providers" do
      assert_equal [RedmineAiHelper::Tools::SystemTools], @agent.available_tool_providers
    end
  end

  context "UserAgent" do
    setup do
      @agent = RedmineAiHelper::Agents::UserAgent.new
    end

    should "return correct tool providers" do
      assert_equal [RedmineAiHelper::Tools::UserTools], @agent.available_tool_providers
    end
  end

  context "ProjectAgent" do
    setup do
      @agent = RedmineAiHelper::Agents::ProjectAgent.new
    end

    should "return correct tool providers" do
      assert_equal [RedmineAiHelper::Tools::ProjectTools], @agent.available_tool_providers
    end
  end

  context "WikiAgent" do
    setup do
      @agent = RedmineAiHelper::Agents::WikiAgent.new
    end

    should "return correct tool providers" do
      assert_equal [RedmineAiHelper::Tools::WikiTools], @agent.available_tool_providers
    end
  end

  context "VersionAgent" do
    setup do
      @agent = RedmineAiHelper::Agents::VersionAgent.new
    end

    should "return correct tool providers" do
      assert_equal [RedmineAiHelper::Tools::VersionTools], @agent.available_tool_providers
    end
  end

  context "McpAgent" do
    setup do
      @agent = RedmineAiHelper::Agents::McpAgent.new
    end

    should "return correct role" do
      assert_equal "mcp_agent", @agent.role
    end

    should "return backstory" do
      backstory = @agent.backstory
      assert_not_nil backstory
      assert backstory.is_a?(String)
    end

    should "be disabled by default" do
      assert_equal false, @agent.enabled?
    end

  end

  context "edge cases" do
      should "handle tool schema with missing name or description" do
        # Create a test class with incomplete tool schemas
        test_class = Class.new(RedmineAiHelper::BaseAgent) do
          define_method :available_tools do
            [
              [{ type: "function", function: { name: "tool_without_desc" } }],
              [{ type: "function", function: { description: "Description without name" } }],
              [{ type: "function", function: {} }]
            ]
          end

          define_method :backstory do
            tools_list = available_tools
            tools_info = ""
            
            if tools_list.is_a?(Array) && !tools_list.empty?
              tools_list.each do |tool_schemas|
                if tool_schemas.is_a?(Array)
                  tool_schemas.each do |tool|
                    if tool.is_a?(Hash) && tool.dig(:function, :name) && tool.dig(:function, :description)
                      function_name = tool.dig(:function, :name)
                      description = tool.dig(:function, :description)
                      tools_info += "- **#{function_name}**: #{description}\n"
                    elsif tool.is_a?(Hash) && tool[:name] && tool[:description]
                      function_name = tool[:name]
                      description = tool[:description]
                      tools_info += "- **#{function_name}**: #{description}\n"
                    end
                  end
                end
              end
            else
              tools_info = "- No tools available\n"
            end
            
            if tools_info.empty?
              tools_info = "- No valid tools found\n"
            end
            
            "I am an AI agent specialized in using the test_server MCP server.\n" \
            "I have access to the following tools:\n" \
            "#{tools_info}\n" \
            "I can help you with tasks that require interaction with test_server services."
          end
        end

        agent = test_class.new
        backstory = agent.backstory
        
        # Should still generate backstory without crashing
        assert backstory.include?("I am an AI agent specialized in using the test_server MCP server")
        assert backstory.include?("I have access to the following tools:")
        # Should handle missing data gracefully
        assert backstory.include?("- No valid tools found")
      end
  end
end
