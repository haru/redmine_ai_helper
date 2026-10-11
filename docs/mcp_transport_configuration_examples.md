# MCP Transport Configuration Examples

This document provides configuration examples for connecting the Redmine AI Helper plugin to external MCP servers. The plugin uses RubyLLM's built-in MCP client, which supports two transports: **stdio** and **Streamable HTTP**.

## Auto-Detection

The transport type is detected from the configuration when `type` is omitted:
- **stdio**: when `command` or `args` is present
- **http** (Streamable HTTP): when `url` is present

## Supported Transports and Restrictions

| Transport | `type` | Notes |
|-----------|--------|-------|
| stdio | `stdio` | Starts a local process. `command` and `args` are passed as an argv array; no shell is involved. |
| Streamable HTTP | `http` | Use `https://`. Plain `http://` is accepted only for `localhost`, `127.0.0.1` and `::1`. |

Not supported (the server is skipped and a warning is written to the AI Helper log):
- The legacy SSE transport (`"type": "sse"`). Use Streamable HTTP (`"type": "http"`) instead.
- Plain `http://` URLs for any host other than the loopback addresses.
- URLs that contain credentials (`https://user:pass@host/...`). Use `headers` instead.

The recognized keys are `type`, `command`, `args`, `env` (stdio) and `url`, `headers` (http). Other keys are ignored.

## stdio Examples

### Basic Command Configuration
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
    }
  }
}
```

### With Environment Variables
```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "xoxb-your-bot-token",
        "SLACK_TEAM_ID": "T01234567"
      }
    }
  }
}
```

### Args Only Configuration
When `command` is omitted, `args` is used as the whole argv:
```json
{
  "mcpServers": {
    "custom_server": {
      "args": ["node", "/path/to/custom-server.js", "--debug"]
    }
  }
}
```

## Streamable HTTP Examples

### Loopback (plain HTTP allowed)
```json
{
  "mcpServers": {
    "local_api": {
      "url": "http://localhost:3000/mcp"
    }
  }
}
```

### HTTPS with Authentication
```json
{
  "mcpServers": {
    "secure_api": {
      "type": "http",
      "url": "https://api.example.com/mcp",
      "headers": {
        "Authorization": "Bearer your-api-token",
        "X-API-Key": "your-api-key"
      }
    }
  }
}
```

## Mixed Configuration

stdio and HTTP servers can be used in the same file:

```json
{
  "mcpServers": {
    "local_filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/user/projects"]
    },
    "remote_database": {
      "url": "https://db-api.example.com/mcp",
      "headers": {
        "Authorization": "Bearer db-access-token"
      }
    }
  }
}
```

## Configuration File Location

Place your configuration file at:
```
/path/to/redmine/config/ai_helper/config.json
```

Restart Redmine after changing it.

## Behavior Notes

- One agent (`AiHelperMcp<ServerName>`) is created per valid server.
- A server that cannot be reached, or whose tool list cannot be retrieved, makes the request that uses its agent fail with an error, which is also logged. The failure is not cached: the next request connects to the server again. Requests that do not use that server are not affected.
- When read-only mode is enabled, all external MCP agents are disabled.

## Troubleshooting

1. **The server does not appear**
   - Check the AI Helper log for a warning naming the server. SSE servers, non-loopback `http://` URLs and URLs with credentials are skipped.
   - Check the JSON syntax of `config.json`.

2. **HTTP connection failures**
   - Verify the URL is reachable from the Redmine server and uses `https://` (or a loopback address).
   - Verify that the server implements the Streamable HTTP transport.

3. **stdio command not found**
   - Verify the command exists in PATH of the Redmine process.
   - Check file permissions and that all required dependencies are installed.
