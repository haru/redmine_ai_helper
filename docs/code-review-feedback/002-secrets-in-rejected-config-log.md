# CRF-002: Rejected MCP server config was logged in full, including credentials

**Date**: 2026-10-11
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `feature/069-ruby-llm-2-1-migration`
**Files**: lib/redmine_ai_helper/util/mcp_server_loader.rb, test/unit/util/mcp_server_loader_test.rb
**Category**: security
**Related**: None

## Feedback

`generate_mcp_agent_classes` logged `#{server_config}` for rejected servers, leaking URL userinfo, `Authorization` headers and `env` values. `secure_url?` masked credentials in its own warning, but the next log line printed them anyway.

## Original Code

```ruby
ai_helper_logger.warn "Invalid configuration for MCP server '#{server_name}': #{server_config}"
```

## Fix

The log now names only the server (error level), never the config. A test goes through `generate_mcp_agent_classes` and asserts no secret appears in any log message.

## Root Cause

The AI added credential masking in the new validator but kept an existing generic log line that interpolated the whole Hash, and the new rejection rules (SSE, plain http, URL credentials) widened the set of configs reaching it. The test called the validator directly, so the second log line was never exercised.

## Prevention

Never interpolate a whole configuration Hash, headers, env or URL into a log message; log only the server name and the reason. Test secret masking through the public entry point that emits every log line, not just the helper.

**Promoted to**: Not yet
