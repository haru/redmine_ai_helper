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
  protect_from_forgery with: :null_session

  before_action :check_mcp_enabled
  before_action :authenticate_mcp_request

  # Handles POST, GET, and DELETE requests for the MCP Streamable HTTP
  # transport. All three verbs are routed here to comply with the MCP spec.
  #
  # @return [void]
  def handle_request
    body_content = request.body.read
    rack_env = request.env.merge("rack.input" => StringIO.new(body_content))
    server = RedmineAiHelper::Mcp::Server.build
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true, enable_json_response: true)

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
