# frozen_string_literal: true

require "redmine_ai_helper/mcp/server"
require "redmine_ai_helper/mcp/session_strategy"

# Controller that exposes the MCP (Model Context Protocol) Streamable HTTP
# endpoint at +/ai_helper/mcp+.
#
# Authentication is stateless and per-request via the +X-Redmine-API-Key+
# header. A Redmine administrator can toggle the endpoint on or off via the
# plugin settings page.
#
# The controller delegates request handling to the MCP gem's
# +StreamableHTTPTransport+ in stateless mode, which handles JSON-RPC
# framing, +initialize+, +tools/list+, and +tools/call+ methods.
class AiHelperMcpController < ApplicationController
  # Authentication is enforced by authenticate_mcp_request below using the
  # X-Redmine-API-Key request header. Because authentication is header-based
  # (not session-cookie-based) and no session state is mutated by this
  # controller, CSRF token verification does not apply. Skipping it here
  # prevents Redmine's handle_unverified_request from rendering 422 for
  # legitimate stateless API-key requests.
  skip_before_action :verify_authenticity_token

  # Skip Redmine's global login_required filter because MCP uses its own
  # stateless API-key authentication via authenticate_mcp_request below.
  # Otherwise Setting.login_required = ON returns 403 before our filter runs
  # and the X-Redmine-API-Key header is never evaluated (Issue #304).
  skip_before_action :check_if_login_required, raise: false

  before_action :check_mcp_enabled
  before_action :authenticate_mcp_request

  # Handles POST, GET, and DELETE requests for the MCP Streamable HTTP
  # transport. All three verbs are routed here to comply with the MCP spec.
  #
  # @return [void]
  def handle_request
    body_content = request.body.read
    parsed_request = begin
                       JSON.parse(body_content)
                     rescue JSON::ParserError
                       nil
                     end

    if parsed_request && parsed_request["method"] == "tools/call"
      tool_name = parsed_request.dig("params", "name")
      unless RedmineAiHelper::Mcp::Server.tool_call_permitted?(tool_name.to_s, user: User.current)
        render json: {
          jsonrpc: "2.0",
          id: parsed_request["id"],
          result: {
            content: [ { type: "text", text: l("ai_helper.mcp.errors.tool_permission_denied") } ],
            isError: true
          }
        }
        return
      end
    end

    rack_env = request.env.merge("rack.input" => StringIO.new(body_content))
    server = RedmineAiHelper::Mcp::Server.build
    # DNS rebinding protection (added in mcp 0.23.0, on by default) validates the
    # Host/Origin headers against a loopback allowlist. It is disabled here because
    # this endpoint authenticates with a stateless X-Redmine-API-Key header rather
    # than ambient browser credentials, so the DNS rebinding threat model does not
    # apply, and the Host varies per Redmine deployment so no fixed allowlist fits.
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server, stateless: true, enable_json_response: true, dns_rebinding_protection: false
    )

    rack_status, rack_headers, body_parts = transport.call(rack_env)

    rack_headers.each { |k, v| response.set_header(k, v) }
    render status: rack_status,
           body: Array(body_parts).join,
           content_type: rack_headers["Content-Type"] || "application/json"
  end

  private

  # Returns HTTP 403 when the MCP server is disabled in plugin settings.
  def check_mcp_enabled
    return if AiHelperSetting.setting.mcp_server_enabled

    render json: { error: l("ai_helper.mcp.errors.disabled") }, status: :forbidden
  end

  # Authenticates via +X-Redmine-API-Key+ header.
  # Returns HTTP 401 on failure and sets +User.current+ on success.
  def authenticate_mcp_request
    user = RedmineAiHelper::Mcp::SessionStrategy.authenticate(request)
    if user
      User.current = user
    else
      render json: { error: l("ai_helper.mcp.errors.unauthorized") }, status: :unauthorized
    end
  end
end
