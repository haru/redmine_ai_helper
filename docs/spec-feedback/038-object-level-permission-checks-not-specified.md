# SF-038: Specified only action permissions and left the permissions on the objects an operation uses unstated

**Date**: 2026-11-02
**Feature**: specs/084-project-management-tools (branch `feature/084-project-management-tools`)
**Artifact**: spec.md (FR-003a added, SC-002)
**Category**: scope-gap
**Related**: None

## Feedback

> "Before each tool runs, always check that the operation can really be performed: the permission for the action, and the permission on the objects it uses."

## What the AI Wrote

FR-003 listed one Redmine permission per operation (add project, edit project, manage members, manage categories, ...). Object-level conditions appeared only for some operations and in scattered places (manageable roles in FR-020/021, selectable parents in FR-015, inherited roles in FR-022); nothing said that the user/group being added must be active and visible, that a category or member belongs to the target project, that a category assignee must be assignable, that custom fields must be visible to the requester, or that the target project must not be archived/closed.

SC-002: "requests from users without permission change nothing and the reason is reported."

## Correction

- New FR-003a: every tool checks, before changing anything, (1) the action permission and (2) the permission/validity of every object it uses; on any failure nothing is changed (no partial change) and the missing permission and object are reported. The per-object list follows Redmine's own UI: target project (visible, AI Helper accessible, not archived, not closed for writes), parent project (allowed parents), publicity / inherit members / modules (their own permissions, using the default creator role at creation), custom fields (visible to the requester), principal to add (active, visible, not yet a member), roles (givable and managed by the requester, not inherited), member (belongs to the project), tracker, category (belongs to the project), category assignee (assignable in the project), module (exists).
- SC-002 now covers missing permissions on any used object.

## Root Cause

The AI modelled authorization as "one permission per action" because that is how Redmine's permission list (`lib/redmine/preparation.rb`) is organised, and treated object checks as validation details for the plan. For write tools called by an LLM, however, every ID in the arguments comes from the model and can point to an object the requester must not touch (a hidden user, another project's category, an inherited role). Redmine's controllers enforce these through their scopes (`Principal.active.visible.not_member_of`, `user.managed_roles`, `project.assignable_users`, `Project#allows_to?`), which a tool that sets attributes directly bypasses unless the spec requires the same checks.

## Prevention

When a spec adds a write tool, list every argument that refers to an existing object and state, for each, the condition under which the requester may use it, taken from the scope Redmine's own UI uses for that choice (grep the controller/helper/view that renders the selection). Require that all checks pass before any change.

**Promoted to**: Not yet
