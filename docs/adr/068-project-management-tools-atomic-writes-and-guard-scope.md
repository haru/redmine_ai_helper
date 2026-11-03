# ADR-068: Project management tools write atomically and state the guard scope precisely

**Date**: 2026-11-03
**Status**: Proposed

## Context

ADR-067 states that every project management tool fetches its target project
through `ProjectWriteGuard`, and that all validations finish before a single
save. A code review of the implementation found that both statements need a
precise scope:

- `create_project` checks its parent with its own check (the parent is not the
  target of an existing-project fetch), and `project_members` uses only the
  AI Helper accessibility check. Neither goes through `ProjectWriteGuard`.
  `create_project` therefore reports a closed parent as
  `Permission denied: add_subprojects`, because Redmine's `allowed_to?` refuses
  writes on closed projects.
- On a saved record, `Project#enabled_module_names=`, `Project#tracker_ids=`,
  and `Member#role_ids=` write to the database at assignment time, before
  `save` runs. When `save` then returns false, the tool returned an error
  while the change was already stored.
- `Project#add_default_member` does not return `false` on a validation error
  (ADR-067 says so). It appends the member with `members <<`, which swallows
  the failure and still returns the (unsaved) Member. The conclusion of
  ADR-067 holds: the failure is silent unless the member is saved with `save!`.

## Decision

1. Every tool that targets an **existing** project fetches it through
   `ProjectWriteGuard`. `create_project` checks the requested parent itself
   (`add_project` for a top-level project, `add_subprojects` on the parent,
   visibility, and AI Helper access); this check has no closed-project guard.
   `project_members` keeps its AI Helper accessibility check.
2. `update_modules`, `add_trackers`, `remove_trackers`, and
   `update_member_roles` run the assignment and the `save` in one
   `ActiveRecord::Base.transaction`. A failed save raises `UserError` inside
   it, so the change is rolled back and the error is still returned as
   `{ error: }`. `remove_member` calls `destroy!` in a transaction, so a member
   that cannot be destroyed raises and keeps its roles.
3. `ProjectWriteGuard#writable_project!` requires a Symbol or Hash permission
   and raises `ArgumentError` for `nil`; both fetches raise `ArgumentError`
   for any other type. A write fetch can no longer run without a permission
   check.
4. List arguments (`tracker_ids`, `role_ids`, `add_role_ids`, `remove_role_ids`,
   `enable`, `disable`, `custom_fields`) are checked for their shape at the
   boundary and rejected with `{ error: }` instead of being coerced with
   `Array()`.
5. `update_category` reports a category of a project the caller cannot see as
   `Category not found`, so neither its existence nor its project id leaks.

ADR-067 stays as written. This ADR refines its decisions 1 and 4 and corrects
its description of `add_default_member`.

## Consequences

- A failed save never leaves a partial change, which matches FR-003a.
- The permission-checked fetch is enforced by the guard itself, not by the
  callers getting the argument right.
- Malformed input from the AI or an MCP client yields a precise error instead
  of a system exception.
- The transaction adds one savepoint per call; the cost is negligible.

## Alternatives Considered

- **Route `create_project`'s parent through `ProjectWriteGuard`.** Rejected: it
  would change the specified error messages (`Parent project not allowed`),
  and the parent is not the object being written.
- **Assign collections only after a successful `save`.** Rejected: the
  associations write immediately for a saved record, so `save` cannot be
  ordered before them without losing validation of the new state.
- **Leave the setters outside a transaction.** Rejected: a validation added by
  another plugin would turn into a stored change reported as a failure.
