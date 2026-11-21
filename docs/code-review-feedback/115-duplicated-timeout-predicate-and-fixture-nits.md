# CRF-115: Timeout predicate and log wording copied into three places, plus test fixture nits

**Date**: 2026-11-21
**Source**: Local AI review (speckit-review-run, 6 agents)
**Feature**: branch `feature/089-ruby-llm-2-2-upgrade`
**Files**: lib/redmine_ai_helper/util/connection_error_helper.rb, lib/redmine_ai_helper/agents/issue_read_agent.rb, lib/redmine_ai_helper/agents/wiki_agent.rb, app/controllers/ai_helper_settings_controller.rb, test/support/connection_errors.rb, test/support/mcp/exits_on_tool_call_server.rb
**Category**: readability
**Related**: CRF-012, CRF-031

## Feedback

The simplify and errors reviews pointed at the same `is_a?(ConnectionError) && timeout?` condition and the same comment in two agents and the controller, with different rescue shapes, and at error logs that gave only `e.message`. Also: the test helper had no explanation of why `raise` sits inside `rescue`, kinds were a bare case, the MCP fixture tool was named `echo` though it never echoes, and a ternary was used for assignment.

## Original Code

```ruby
if e.is_a?(RubyLLM::ConnectionError) && e.timeout?   # x3, with slightly different shapes
```

## Fix

`ConnectionErrorHelper.timeout?`/`describe` (adds the cause class), one rescue shape in both agents, the helper moved to `test/support/connection_errors.rb` with `KINDS`, an `:ssl_error` kind and a comment, the tool renamed `exit_now`, `if/else` for the reply.

## Root Cause

ADR-074 rejected a shared helper as "wrapping one library call" while three call sites already existed; the copies were not compared side by side after the second one was written.

## Prevention

When the same condition or log wording appears at a third call site, extract it in the same change instead of recording "inline" as a decision; name test fixtures after what they do.

**Promoted to**: Not yet
