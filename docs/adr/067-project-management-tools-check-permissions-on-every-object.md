# ADR-067: Project management tools check permissions on every object they use

**Date**: 2026-11-03
**Status**: Proposed

## Context

The project management tools (`ProjectWriteTools`, `MemberTools`,
`CategoryTools`) let the AI create and update projects, modules, trackers,
members, and issue categories. Redmine's own screens guard these operations
with controller filters and with `safe_attributes=`, and several of those
guards fail silently:

- `Project#safe_attributes=` drops `is_public`, `inherit_members`,
  `enabled_module_names`, custom fields, and `parent_id` when the user lacks
  the matching permission. The save then succeeds with the old value, so the
  AI would report a change that was never made (research R-003). The parent
  case is then reported only as `Parent is invalid` by `validate_parent`,
  which names neither the missing permission nor the target (R-002).
- Redmine does not validate the assignee of an issue category against the
  users who can be assigned in the project.
- `Project#add_default_member` returns `false` on a validation error instead
  of raising, so a project could be created without its creator as a member
  (R-005).

A tool that acts on the user's behalf must also not enable the `ai_helper`
module for a creator who has no right to select modules (R-004).

## Decision

1. Every tool fetches the target project through `ProjectWriteGuard`, which
   checks, in a fixed order, that the project exists and is visible, is
   accessible via AI Helper, is not closed (writes only), has the
   `issue_tracking` module when required, and that the current user holds the
   required permission. The permission is checked on the project, and for
   `update_category` on the project of the category, never on another one.
2. Attributes that Redmine would silently drop or not validate are judged
   explicitly before assignment, with the Redmine API itself
   (`safe_attribute?`, `allowed_parents`, `editable_custom_field_values`,
   `assignable_users`), and rejected with an error that names the missing
   permission and the target (ADR-047 takes the same approach for versions).
3. On creation, the `ai_helper` module is enabled only when
   `safe_attribute?("enabled_module_names", User.current)` is true. The result
   reports `ai_helper_module_enabled` and `ai_helper_accessible` separately.
4. All validations finish before a single save. `create_project` saves the
   project and the creator's membership in one transaction, with the
   membership saved by `save!`.
5. Actions that are hard to undo (`create_project`, making a project public,
   `remove_member`, disabling the `ai_helper` module) require the AI to confirm
   with the user first. This is stated in the tool description (also shown in
   MCP `tools/list`) and in the ProjectAgent backstory; the tools do not
   verify consent.
6. User-caused failures are returned as `{ error: }` and system failures are
   raised (ADR-048). No tool deletes, closes, or archives data.

This does not supersede ADR-047 or ADR-048; it applies them to a new set of
tools.

## Consequences

- The AI never believes a value was set when Redmine dropped it.
- The same input that Redmine's UI accepts silently can be an error here.
- Permission rules stay in Redmine; the plugin only calls Redmine's own
  predicates. The cost is one explicit check per silently dropped attribute.
- A non-admin creator whose default role lacks `view_ai_helper` gets a project
  that the AI cannot operate; the result says so.
- The confirmation duty depends on the model following instructions, so it is
  not a guarantee.

## Alternatives Considered

- **Rely on the `save` validation errors only.** Rejected: the dropped
  attributes raise no error, and `Parent is invalid` does not tell the user
  which permission or object is missing (R-002, R-003).
- **Silently drop the attributes as Redmine does.** Rejected: it contradicts
  ADR-047, and the AI would misreport the result (R-003).
- **Enable the `ai_helper` module after creation with `enable_module!`.**
  Rejected: it would enable the module regardless of the creator's right to
  select modules (R-004).
- **Call `add_default_member` and ignore its return value, as the Redmine
  controller does.** Rejected: a failure would leave a project without its
  creator, which breaks the rule that nothing is partly changed (R-005, R-016).
