# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/mcp/server"

class McpServerBuilderTest < ActiveSupport::TestCase
  def setup
    AiHelperSetting.delete_all
    @setting = AiHelperSetting.find_or_create
    @admin_user = User.find(1)
    @non_admin_user = User.find(2)
  end

  context "McpServerBuilder.build" do
    should "return an MCP::Server instance" do
      server = RedmineAiHelper::Mcp::Server.build

      assert_instance_of MCP::Server, server
    end

    should "include tools from registered BaseTools subclasses" do
      server = RedmineAiHelper::Mcp::Server.build

      assert_operator server.tools.size, :>=, 1, "server should have at least one tool"
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

  context "mcp_tool_allowed?" do
    should "return true when tool has no requirements" do
      klass = Class.new(RedmineAiHelper::BaseTools)
      result = RedmineAiHelper::Mcp::Server.send(:mcp_tool_allowed?, klass, user: @admin_user)

      assert result, "expected true when no requirements"
    end

    should "return false when vector_db_enabled required but disabled" do
      @setting.update_column(:vector_search_enabled, false)
      klass = Class.new(RedmineAiHelper::BaseTools)
      klass.requires(vector_db_enabled: true)
      result = RedmineAiHelper::Mcp::Server.send(:mcp_tool_allowed?, klass, user: @admin_user)

      assert_not result, "expected false when vector_db_enabled required but disabled"
    end

    should "return false when admin required but user is non-admin" do
      klass = Class.new(RedmineAiHelper::BaseTools)
      klass.requires(admin: true)
      result = RedmineAiHelper::Mcp::Server.send(:mcp_tool_allowed?, klass, user: @non_admin_user)

      assert_not result, "expected false when admin required but user is non-admin"
    end

    should "return true when admin required and user is admin" do
      klass = Class.new(RedmineAiHelper::BaseTools)
      klass.requires(admin: true)
      result = RedmineAiHelper::Mcp::Server.send(:mcp_tool_allowed?, klass, user: @admin_user)

      assert result, "expected true when admin required and user is admin"
    end

    should "return true when vector_db_enabled required and enabled" do
      @setting.update_column(:vector_search_enabled, true)
      klass = Class.new(RedmineAiHelper::BaseTools)
      klass.requires(vector_db_enabled: true)
      result = RedmineAiHelper::Mcp::Server.send(:mcp_tool_allowed?, klass, user: @non_admin_user)

      assert result, "expected true when vector_db_enabled required and enabled"
    end

    should "return true when all conditions met" do
      @setting.update_column(:vector_search_enabled, true)
      klass = Class.new(RedmineAiHelper::BaseTools)
      klass.requires(vector_db_enabled: true, admin: true)
      result = RedmineAiHelper::Mcp::Server.send(:mcp_tool_allowed?, klass, user: @admin_user)

      assert result, "expected true when all conditions met"
    end

    should "return false when one of multiple conditions is not met" do
      @setting.update_column(:vector_search_enabled, false)
      klass = Class.new(RedmineAiHelper::BaseTools)
      klass.requires(vector_db_enabled: true, admin: true)
      result = RedmineAiHelper::Mcp::Server.send(:mcp_tool_allowed?, klass, user: @admin_user)

      assert_not result, "expected false when vector_db_enabled not met"
    end
  end

  context "read_only_mode" do
    should "exclude write tools from the built server when read_only_mode is enabled" do
      @setting.update_column(:read_only_mode, true)

      server = RedmineAiHelper::Mcp::Server.build

      write_tool_names.each do |tool_name|
        assert_not server.tools.key?(tool_name), "expected #{tool_name} to be excluded when read_only_mode is enabled"
      end
      assert server.tools.key?("search_issues"), "expected read tools to remain when read_only_mode is enabled"
    end

    should "include write tools in the built server when read_only_mode is disabled" do
      @setting.update_column(:read_only_mode, false)

      server = RedmineAiHelper::Mcp::Server.build

      write_tool_names.each do |tool_name|
        assert server.tools.key?(tool_name), "expected #{tool_name} to be included when read_only_mode is disabled"
      end
    end

    should "deny tool_call_permitted? for write tools when read_only_mode is enabled" do
      @setting.update_column(:read_only_mode, true)

      write_tool_names.each do |tool_name|
        result = RedmineAiHelper::Mcp::Server.tool_call_permitted?(tool_name, user: @admin_user)

        assert_not result, "expected #{tool_name} to be denied when read_only_mode is enabled"
      end
    end

    should "allow tool_call_permitted? for write tools when read_only_mode is disabled" do
      @setting.update_column(:read_only_mode, false)

      write_tool_names.each do |tool_name|
        result = RedmineAiHelper::Mcp::Server.tool_call_permitted?(tool_name, user: @admin_user)

        assert result, "expected #{tool_name} to be allowed when read_only_mode is disabled"
      end
    end
  end

  private

  def write_tool_names
    %w[create_new_issue update_issue wiki_add_page wiki_update_page wiki_delete_page]
  end
end
