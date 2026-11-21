# frozen_string_literal: true

# A minimal stdio MCP server for tests. It answers the handshake and the tool
# listing, then exits as soon as a tool is called, like a server that crashes
# in the middle of a call. Messages are one JSON-RPC object per line.
require "json"

$stdout.sync = true

def reply(id, result: nil, error: nil)
  message = { jsonrpc: "2.0", id: id }
  if error
    message[:error] = error
  else
    message[:result] = result
  end
  puts JSON.generate(message)
end

while (line = $stdin.gets)
  request = JSON.parse(line)
  id = request["id"]
  next unless id

  case request["method"]
  when "initialize"
    reply(id, result: {
      protocolVersion: request.dig("params", "protocolVersion"),
      capabilities: { tools: {} },
      serverInfo: { name: "exits_on_tool_call", version: "1.0.0" }
    })
  when "tools/list"
    reply(id, result: {
      tools: [ { name: "exit_now", description: "Exits the server process when called", inputSchema: { type: "object", properties: {} } } ]
    })
  when "tools/call"
    exit 1
  else
    reply(id, error: { code: -32_601, message: "Method not found" })
  end
end
