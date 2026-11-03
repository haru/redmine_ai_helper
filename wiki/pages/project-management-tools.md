---
title: Project Management Tools
type: component
sources: [S060]
updated: 2026-11-03
---

# Project Management Tools

Feature 084 gives ProjectAgent tools to create and update projects, switch
modules, assign trackers, manage members and issue categories (S060). Part of
the [Tool System](./tool-system.md); the same strict-input approach as
[Version Write Tools](./version-write-tools-error-policy.md).

## Tool classes

| Class | Functions |
|---|---|
| `ProjectWriteTools` | `create_project`, `update_project`, `update_modules`, `add_trackers`, `remove_trackers` |
| `ProjectTools` (extended) | `capable_project_props`, `project_members` |
| `MemberTools` | `find_member_candidates`, `list_managed_roles`, `add_member`, `update_member_roles`, `remove_member` |
| `CategoryTools` | `list_categories`, `create_category`, `update_category` |

Writes use `write: true`, so read-only mode drops them in chat and MCP (S060).
No tool deletes, closes, or archives a project, category, or other data;
`remove_member` and `remove_trackers` only unassign (S060). Tests pin this.

## Where it differs from standard Redmine

- **Rejected, not silently dropped.** Redmine's `safe_attributes=` discards
  `is_public`, `inherit_members`, modules, custom fields, and `parent_id` when
  the user lacks the permission. The tools judge them first and return an
  error naming the permission (S060, ADR-067).
- **Category assignee is checked** against `project.assignable_users`, which
  Redmine itself does not validate (S060).
- **`ai_helper` module on creation** is enabled only when the creator may
  select modules; the result carries `ai_helper_module_enabled` and
  `ai_helper_accessible` because a non-admin default role without
  `view_ai_helper` leaves the project unusable by the AI (S060).
- **Creator membership** is saved with the project in one transaction;
  for non-admin creators, creation is refused up front if no default member
  role exists, where Redmine's UI would create a project without the creator
  as member (S060).
- **Object-level permission:** every tool that targets an existing project
  checks that project via `ProjectWriteGuard` (`update_category` uses the
  category's project; a category of an invisible project is reported as not
  found). `create_project` checks the requested parent itself, and
  `project_members` checks only AI Helper access. `list_categories` requires
  only visibility, AI Helper access, and the issue_tracking module (no
  permission) (S060, ADR-068).
- **Atomic writes:** module, tracker, and member-role changes write at
  assignment time in Redmine, so each runs with its `save` in one transaction
  and a failed save changes nothing (S060, ADR-068).
- **Confirmation** before `create_project`, making a project public,
  `remove_member`, and disabling `ai_helper` is requested in tool descriptions
  and the backstory, not enforced by the tools (S060).

## `project_members` output

Now built from `project.memberships`, so groups and locked users appear. Old
keys are unchanged; added: `member_id`, `type` (user/group), `status`
(active/registered/locked), `deletable`, and per role `inherited`,
`inherited_from`, `editable` (S060). Callers such as IssueWriteAgent should
read `type`/`status` before choosing an assignee (S060).
