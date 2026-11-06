# SF-041: Added a near-duplicate tool instead of asking whether to extend the existing one

**Date**: 2026-11-02
**Feature**: specs/084-project-management-tools (branch `feature/084-project-management-tools`)
**Artifact**: research.md, plan.md, data-model.md, contracts/member_tools.md
**Category**: unconfirmed-assumption
**Related**: SF-027

## Feedback

Asked whether to add a new member-listing tool or extend the existing `project_members`, the user chose "extend the existing tool" (accepting that its output changes).

## What the AI Wrote

research.md R-010 decided:

> The existing `ProjectTools#project_members` returns `project.members` (active users only, no groups), so it lacks what removing a group or changing its roles needs. Keep the existing tool unchanged and add `MemberTools#list_memberships`.
>
> Alternatives considered: make `project_members` group-aware → changes the existing tool's output and is out of scope.

The plan, data model and contract were written around `list_memberships`; the question was asked only after the plan was finished.

## Correction

- Removed `list_memberships`. Added research R-018: `project_members` is built from `project.memberships` (groups and locked users included), keeps every existing key (`user_id`, `login`, `user_name`, `roles[].id`, `roles[].name`) and adds `member_id`, `type`, `status`, `deletable`, `roles[].inherited`, `roles[].inherited_from`, `roles[].editable`.
- Listed every caller found with `grep -rn project_members` and the `ProjectTools` users (ProjectAgent, IssueWriteAgent, IssueReadAgent, MCP clients, existing tests) with the impact on each; the tool description now tells the LLM to check `type`/`status` before picking an issue assignee.
- Updated plan.md, data-model.md and contracts/member_tools.md to the extended tool.

## Root Cause

The AI applied "do not change existing behaviour without consulting" as "avoid changing it" and resolved the gap by adding a second tool that returns almost the same list. The rule asks for consultation, not avoidance; the choice between extending and duplicating was the user's to make, and the AI settled it in the plan and wrote three artifacts around it before asking.

## Prevention

When a feature needs data that an existing tool almost returns, do not add a near-duplicate tool in the plan: list the existing tool's callers and the impact of extending it, and ask the user "extend the existing tool or add a new one" before writing the design around either option.

**Promoted to**: Not yet
