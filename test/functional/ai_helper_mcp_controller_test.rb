# frozen_string_literal: true

require_relative "../test_helper"

class AiHelperMcpControllerTest < ActionController::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users,
           :issue_categories, :versions, :members, :member_roles, :roles, :user_preferences

  def setup
    @controller = AiHelperMcpController.new
    @request = ActionController::TestRequest.create(@controller.class)
    @response = ActionDispatch::TestResponse.create

    AiHelperSetting.delete_all
    @setting = AiHelperSetting.find_or_create
    @setting.update_column(:mcp_server_enabled, true)

    @user = User.find(1) # admin user
    @api_key = @user.api_key
  end

  # ─── Authentication before_action (T011) ──────────────────────────────────

  context "authentication" do
    should "return 401 when X-Redmine-API-Key header is missing" do
      post :handle_request, body: initialize_payload, as: :json
      assert_response 401
    end

    should "return 401 when X-Redmine-API-Key is invalid" do
      @request.headers["X-Redmine-API-Key"] = "definitely_invalid_key_xyz"
      @request.headers["Accept"] = "application/json, text/event-stream"
      post :handle_request, body: initialize_payload, as: :json
      assert_response 401
    end

    should "succeed when X-Redmine-API-Key is valid" do
      set_valid_auth_headers
      post :handle_request, body: initialize_payload, as: :json
      assert_response :success
    end
  end

  # ─── MCP enabled check before_action (T011) ────────────────────────────────

  context "MCP enabled check" do
    should "return 403 when MCP server is disabled" do
      @setting.update_column(:mcp_server_enabled, false)
      set_valid_auth_headers
      post :handle_request, body: initialize_payload, as: :json
      assert_response 403
    end

    should "allow requests when MCP server is enabled" do
      set_valid_auth_headers
      post :handle_request, body: initialize_payload, as: :json
      assert_response :success
    end
  end

  # ─── initialize (T012) ─────────────────────────────────────────────────────

  context "initialize method" do
    setup { set_valid_auth_headers }

    should "return protocolVersion in result" do
      post :handle_request, body: initialize_payload, as: :json
      body = JSON.parse(@response.body)
      assert body.dig("result", "protocolVersion").present?,
             "expected protocolVersion in result"
    end

    should "return capabilities in result" do
      post :handle_request, body: initialize_payload, as: :json
      body = JSON.parse(@response.body)
      assert body.dig("result", "capabilities").present?,
             "expected capabilities in result"
    end

    should "return serverInfo in result" do
      post :handle_request, body: initialize_payload, as: :json
      body = JSON.parse(@response.body)
      assert body.dig("result", "serverInfo", "name").present?,
             "expected serverInfo.name in result"
    end
  end

  # ─── notifications/initialized (T012) ──────────────────────────────────────

  context "notifications/initialized" do
    setup { set_valid_auth_headers }

    should "return 202 Accepted" do
      post :handle_request, body: notification_initialized_payload, as: :json
      assert_response 202
    end
  end

  # ─── tools/list (T013) ─────────────────────────────────────────────────────

  context "tools/list" do
    setup { set_valid_auth_headers }

    should "return a non-empty tools array" do
      post :handle_request, body: tools_list_payload, as: :json
      body = JSON.parse(@response.body)
      tools = body.dig("result", "tools")
      assert tools.is_a?(Array) && tools.any?,
             "expected non-empty tools array, got: #{tools.inspect}"
    end

    should "return tools with name, description, and inputSchema" do
      post :handle_request, body: tools_list_payload, as: :json
      tools = JSON.parse(@response.body).dig("result", "tools")
      tools.each do |tool|
        assert tool["name"].present?, "tool missing name"
        assert tool["inputSchema"].present?, "tool missing inputSchema"
      end
    end

    should "include search_issues in the tool list" do
      post :handle_request, body: tools_list_payload, as: :json
      tools = JSON.parse(@response.body).dig("result", "tools")
      names = tools.map { |t| t["name"] }
      assert_includes names, "search_issues"
    end

    should "include list_projects in the tool list" do
      post :handle_request, body: tools_list_payload, as: :json
      tools = JSON.parse(@response.body).dig("result", "tools")
      names = tools.map { |t| t["name"] }
      assert_includes names, "list_projects"
    end

    should "exclude get_system_info from the tool list" do
      post :handle_request, body: tools_list_payload, as: :json
      tools = JSON.parse(@response.body).dig("result", "tools")
      names = tools.map { |t| t["name"] }
      assert_not_includes names, "get_system_info"
    end
  end

  # ─── tools/call read tools (T014) ──────────────────────────────────────────

  context "tools/call" do
    setup { set_valid_auth_headers }

    should "return content array with type text on success" do
      RedmineAiHelper::Tools::ProjectTools.any_instance.stubs(:list_projects).returns([{ id: 1, name: "Test" }])
      post :handle_request, body: tools_call_payload("list_projects", {}), as: :json
      body = JSON.parse(@response.body)
      content = body.dig("result", "content")
      assert content.is_a?(Array) && content.any?, "expected content array"
      assert_equal "text", content.first["type"]
    end

    should "return isError false on success" do
      RedmineAiHelper::Tools::ProjectTools.any_instance.stubs(:list_projects).returns([{ id: 1, name: "Test" }])
      post :handle_request, body: tools_call_payload("list_projects", {}), as: :json
      body = JSON.parse(@response.body)
      assert_equal false, body.dig("result", "isError")
    end
  end

  # ─── tools/call write tools (T020) ─────────────────────────────────────────

  context "tools/call write tools" do
    setup { set_valid_auth_headers }

    should "return isError false when create_new_issue succeeds" do
      fake_issue = { id: 99, subject: "New Issue" }
      RedmineAiHelper::Tools::IssueUpdateTools.any_instance.stubs(:create_new_issue).returns(fake_issue)
      post :handle_request,
           body: tools_call_payload("create_new_issue", { project_id: 1, tracker_id: 1, subject: "Test", status_id: 1 }),
           as: :json
      body = JSON.parse(@response.body)
      assert_equal false, body.dig("result", "isError"), "expected isError false on success"
      content = body.dig("result", "content")
      assert content.is_a?(Array) && content.any?, "expected non-empty content array"
    end

    should "return isError false when update_issue succeeds" do
      fake_issue = { id: 1, subject: "Updated Subject" }
      RedmineAiHelper::Tools::IssueUpdateTools.any_instance.stubs(:update_issue).returns(fake_issue)
      post :handle_request,
           body: tools_call_payload("update_issue", { issue_id: 1, subject: "Updated Subject" }),
           as: :json
      body = JSON.parse(@response.body)
      assert_equal false, body.dig("result", "isError"), "expected isError false on success"
    end
  end

  # ─── tools/call permission enforcement (T021) ──────────────────────────────

  context "tools/call permission enforcement" do
    setup { set_valid_auth_headers }

    should "return isError true when create_new_issue raises permission error" do
      RedmineAiHelper::Tools::IssueUpdateTools.any_instance.stubs(:create_new_issue).raises(RuntimeError, "Permission denied")
      post :handle_request,
           body: tools_call_payload("create_new_issue", { project_id: 1, tracker_id: 1, subject: "Test", status_id: 1 }),
           as: :json
      body = JSON.parse(@response.body)
      assert_equal true, body.dig("result", "isError"), "expected isError true on permission denied"
      content = body.dig("result", "content")
      assert content.is_a?(Array) && content.any?, "expected error content array"
      assert_equal "text", content.first["type"]
      assert_match(/Permission denied/, content.first["text"])
    end

    should "not raise an exception when a write tool raises an error" do
      RedmineAiHelper::Tools::IssueUpdateTools.any_instance.stubs(:update_issue).raises(ActiveRecord::RecordNotFound, "Couldn't find Issue")
      post :handle_request,
           body: tools_call_payload("update_issue", { issue_id: 99999, subject: "x" }),
           as: :json
      assert_response :success
      body = JSON.parse(@response.body)
      assert_equal true, body.dig("result", "isError"), "expected isError true on record not found"
    end
  end

  private

  def set_valid_auth_headers
    @request.headers["X-Redmine-API-Key"] = @api_key
    @request.headers["Accept"] = "application/json, text/event-stream"
  end

  def initialize_payload
    {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-03-26",
        capabilities: {},
        clientInfo: { name: "test-client", version: "1.0" }
      }
    }.to_json
  end

  def notification_initialized_payload
    {
      jsonrpc: "2.0",
      method: "notifications/initialized"
    }.to_json
  end

  def tools_list_payload
    {
      jsonrpc: "2.0",
      id: 2,
      method: "tools/list"
    }.to_json
  end

  def tools_call_payload(tool_name, arguments)
    {
      jsonrpc: "2.0",
      id: 3,
      method: "tools/call",
      params: { name: tool_name, arguments: arguments }
    }.to_json
  end
end
