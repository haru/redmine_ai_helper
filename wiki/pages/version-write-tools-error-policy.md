---
title: "Version Write Tools: Strict Input & Error Results"
type: decision
sources: [S041]
updated: 2026-10-08
---

# Version Write Tools: Strict Input & Error Results

Two deliberate departures from convention in feature 068, recorded as ADR-047
and ADR-048 (S041). Component details: [Version Write Tools](./version-write-tools.md).

## ADR-047: reject disallowed sharing / custom fields

Redmine silently drops a disallowed `sharing` (controller `attributes.delete`)
and uneditable custom fields (`Version#safe_attributes=` `reject!`). The tools
instead error **before assignment**, so the AI never believes it shared or set
something it did not (S041).

- `sharing` not in `version.allowed_sharings(User.current)` → error listing the
  allowed values.
- `field_id` not in `version.editable_custom_field_values(User.current)` →
  error listing editable IDs and names.
- Redmine's own methods decide permissibility; the rules (system = admin only,
  hierarchy/tree = root project + `:manage_versions`, current value always
  allowed) are not reimplemented. New versions are checked on
  `project.versions.build` (S041).
- Rejected: follow Redmine and drop silently (S041).

## ADR-048: user mistakes → `{ error: }`, system failures → exceptions

Existing tools always `raise`. In chat, RubyLLM 1.16.0 does not rescue tool
exceptions: they propagate to `BaseAgent#dispatch`, abort the whole tool loop
and fail the step, so remaining calls in the same response never run and the AI
sees nothing. "Create 4 versions, #1 has a duplicate name" would lose the other
3, violating FR-018 (S041).

- **User mistakes** (missing args, unknown/invisible project or version, outside
  AI Helper scope, no permission, disallowed sharing/field, Redmine validation
  errors, version in use) → `{ error: "<English message>" }`, which RubyLLM
  hands to the AI as a tool result. MCP's `ToolAdapter` turns both errors and
  exceptions into `isError: true`, so MCP clients see no change (S041).
- **System failures** (DB down, SQL error, `NoMethodError`) → exception,
  unrescued, logged by `dispatch`; hiding them from the AI would delay
  diagnosis and violates the "no silent fallback" principle (S041).
- Mechanism: `BaseTools::UserError < StandardError` plus private
  `user_errors_as_result { }` rescuing **only** `UserError`. Used only by the 4
  new functions; existing tools and `define_function` are unchanged (S041).
- Rejected: always `raise` (breaks FR-018); converting all tools' exceptions in
  `define_function` (changes every tool, leaks system errors to the AI, YAGNI);
  rescuing all `StandardError` (loses logging) (S041).

Whether to extend this to existing tools is undecided.

Related: [Tool System](./tool-system.md)
