---
title: Log File Access Tools
type: component
sources: [S036]
updated: 2026-09-23
---

# Log File Access Tools

Administrators can inspect the Redmine application log and the AI Helper plugin
log from chat or [MCP](./mcp-server-endpoint.md), via three functions added to
the existing `SystemTools` provider used by `SystemAgent`: `get_log_file_info`,
`read_log_tail` and `search_log` (S036). They are part of the
[Tool System](./tool-system.md); the file is chosen by
[Log File Location Resolution](./log-file-location-resolution.md) and read by
the [Log File Reader](./log-file-reader.md) (S036).

## Gating: admin → setting → input, before any file is opened

Each function checks, in this order, and `raise`s on failure without touching
the file (S036):

1. `User.current.admin?` — same message style as `get_system_info`.
2. `AiHelperSetting.log_access_enabled?` — the error names the *"Allow log
   access"* setting as the way to enable it.
3. Input validation.

Admin comes first so non-admins never learn the setting's state (S036). A
`raise` inside a tool becomes `TaskResponse.create_error(e.message)` in
`BaseAgent#dispatch` and reaches the user through the leader agent — the same
convention as the rest of `tools/` (S036).

**The tools stay visible when the setting is off.** Hiding them would make it
impossible to tell the admin the feature is disabled and how to turn it on, so
a new `BaseTools.requires` key was rejected (S036). A separate `LogTools`
provider was also rejected: `SystemTools` already declares `requires admin:
true`, and three functions don't justify a new class (S036).

Over MCP, `requires admin: true` hides the tools from non-admins,
`tool_adapter.rb` re-checks admin at call time, and the in-method setting check
still applies — both paths share the same method, so one check suffices (S036).

## The setting

`ai_helper_settings.log_access_enabled` (boolean, NOT NULL, default `false`),
exposed via `safe_attributes` and a checkbox on the settings page's General
tab, localized in all 8 locales — the same pattern as `read_only_mode` and
`all_projects_scope` (S036). Its description states that enabling it sends log
contents to the LLM provider (S036). A DB setting was chosen over
`config.yml` so it can be toggled without a restart (S036).

## Inputs and limits

- `log_type`: `"redmine"` (default) or `"ai_helper"`, as a JSON Schema `enum`
  and re-validated at runtime — arbitrary paths are not accepted (S036).
- `lines`, `max_matches` ≥ 1 and `context_lines` ≥ 0 must be integers; values
  above the maximum are clamped and flagged `*_capped: true`; an empty or
  whitespace-only `keyword` is an input error (S036).
- Results and error messages contain only `File.basename(path)`, never an
  absolute path (S036).

**Risk**: the spec's maximums (200 matches × (1 + 2×10 context lines) × 2,000
characters ≈ 8.4 M characters) can exceed an LLM context. The limits were left
as specified; tool descriptions and the prompt tell the LLM to start from the
defaults (50 matches, 0 context) (S036).

## Prompt guidance

`system_agent/backstory.yml` / `backstory_ja.yml` add log access (admin-only,
setting-gated) to `SystemAgent`'s scope and tell the LLM to (S036):

- cite the log lines behind a conclusion (line number or `lines_from_end` plus
  the text) and not present guesses as facts;
- default to the Redmine log, and use `log_type: "ai_helper"` for AI Helper
  issues;
- start with default sizes and widen only when needed.

A dedicated `LogAgent` was rejected — the spec places the feature in
`SystemAgent` (S036).

## Out of scope

Rotated/compressed logs, other plugins' or web/app-server logs, configurable
limits, extra masking beyond Redmine's parameter filter, and any write
operation on logs (S036).

## Related

- [Tool System](./tool-system.md) · [MCP Server Endpoint](./mcp-server-endpoint.md)
- [Log File Location Resolution](./log-file-location-resolution.md) ·
  [Log File Reader](./log-file-reader.md)
- [All-Projects Data-Access Scope](./all-projects-data-access-scope.md) — the
  other global opt-in admin setting.
