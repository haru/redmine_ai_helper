# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/mcp/server"

class McpServerBuilderTest < ActiveSupport::TestCase
  context "McpServerBuilder.build" do
    should "return an MCP::Server instance" do
      server = RedmineAiHelper::Mcp::Server.build
      assert_instance_of MCP::Server, server
    end

    should "include tools from registered BaseTools subclasses" do
      server = RedmineAiHelper::Mcp::Server.build
      assert server.tools.size >= 1, "server should have at least one tool"
    end

    should "exclude SystemTools (get_system_info, list_plugins)" do
      server = RedmineAiHelper::Mcp::Server.build
      tool_names = server.tools.keys
      assert_not_includes tool_names, "get_system_info"
      assert_not_includes tool_names, "list_plugins"
    end

    should "include search_issues from IssueSearchTools" do
      server = RedmineAiHelper::Mcp::Server.build
      assert server.tools.key?("search_issues"),
             "expected search_issues tool to be present"
    end

    should "include list_projects from ProjectTools" do
      server = RedmineAiHelper::Mcp::Server.build
      assert server.tools.key?("list_projects"),
             "expected list_projects tool to be present"
    end
  end
end
