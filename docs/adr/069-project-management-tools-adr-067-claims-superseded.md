# ADR-069: State which ADR-067 claims ADR-068 supersedes, and type-check boolean tool arguments

**Date**: 2026-11-03
**Status**: Proposed

## Context

ADR-068 corrects three statements of ADR-067, but it also says
"ADR-067 stays as written". A reader of ADR-067 alone gets no hint that
any part of it no longer holds, and the sentence in ADR-068 suggests that
both ADRs are in force as written. They contradict each other. Both ADRs are
merged, and ADRs are append-only, so neither can be edited. GitHub Copilot
raised this on PR #549.

The same review found that boolean tool arguments were not type-checked
(CRF-093). Chat tool calls through RubyLLM are not validated against the JSON
schema. (MCP calls are validated, because the mcp gem's
`validate_tool_call_arguments` defaults to true.) Rails casts a string such as
`"no"` to `true` for `is_public` and `inherit_members`. A `== true` comparison
for `clear_parent` and `clear_assigned_to` silently ignored values such as
`"true"`. ADR-068 decision 4 covered list arguments only.

## Decision

1. The following ADR-067 statements are **superseded** by ADR-068. Read
   ADR-068 for the current rule:
   - Decision 1, "Every tool fetches the target project through
     `ProjectWriteGuard`". Superseded by ADR-068 decision 1: only tools that
     target an **existing** project use the guard. `create_project` checks its
     parent itself, without a closed-project guard. `project_members` uses
     only the AI Helper accessibility check.
   - Decision 4, "All validations finish before a single save". Superseded
     by ADR-068 decision 2: collection setters on a saved record write at
     assignment time. Assignment and `save` therefore run in one transaction,
     and a failed save rolls the change back.
   - Context, "`Project#add_default_member` returns `false` on a validation
     error". Corrected by ADR-068: it returns the unsaved Member and swallows
     the failure. ADR-067's conclusion, that the member is saved with
     `save!`, is unchanged.
2. The sentence "ADR-067 stays as written" in ADR-068 is withdrawn. All other
   decisions of ADR-067 (2, 3, 5, and 6) remain in force.
3. ADR-068 decision 4 is extended to boolean arguments. `is_public`,
   `inherit_members`, `clear_parent` (`create_project` / `update_project`), and
   `clear_assigned_to` (`update_category`) accept only `true`, `false`, or
   `nil`. Any other value is rejected with
   `{ error: "<name> must be true or false" }` by
   `BaseTools#validate_booleans!` before the permission checks.

## Consequences

- ADR-067, ADR-068, and this ADR can be read together without contradiction.
  This ADR lists every superseded statement in one place.
- ADR-067 still does not point forward to its corrections. Readers have to
  find this ADR through the ADR index.
- A malformed boolean from the chat no longer flips a project to public, or
  turns a "clear" request into a silent no-op.

## Alternatives Considered

- **Edit ADR-067 and ADR-068 in place.** Rejected: both are merged, and ADRs
  are append-only.
- **Mark ADR-067 as "Superseded by ADR-068".** Rejected: most of its decisions
  (2, 3, 5, and 6) are still in force. A whole-ADR status would tell readers to
  ignore them.
- **Leave the contradiction and only close the review thread.** Rejected: the
  contradiction would mislead later changes to the guard or to project
  creation.
