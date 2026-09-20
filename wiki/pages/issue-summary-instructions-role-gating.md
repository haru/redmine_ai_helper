---
title: Issue Summary Instructions & Role Gating
type: decision
sources: [S035]
updated: 2026-09-20
---

# Issue Summary Instructions & Role Gating

Feature 058 adds a project-level `issue_summary_instructions` setting (same
family as `issue_draft_instructions`, `assignment_suggestion_instructions`)
that lets a project admin steer `IssueReadAgent#issue_summary`, and lets that
guidance reference the **role** (not just the name) of an issue's author,
assignee, and commenters (S035). See
[Issue Summary Instructions: Prompt Template & Settings](./issue-summary-instructions-prompt-template.md)
for how the setting reaches the prompt without touching it when unset.

## Decision: resolve roles with one `Member` bulk query

```ruby
Member.where(project_id: project.id, user_id: principal_ids).includes(:roles)
```

`Member`'s `user_id` foreign key actually stores a **Principal** ID
(`app/models/principal.rb:31`, `has_many :members, foreign_key: 'user_id'`),
so one query resolves roles for both `User` and `Group` assignees with no
type branch (S035).

This also satisfies two constraints as a side effect of using membership
rather than a per-user helper:
- Non-members return no rows, so built-in roles (Non member / Anonymous) are
  never included — `User#roles_for_project` would return
  `project.override_roles(builtin_role)` on public projects instead.
- Roles inherited from group membership (Redmine materializes an
  `inherited_from` `MemberRole` onto the user's own `Member` when they join a
  group — `app/models/group.rb:74-88`, `app/models/member_role.rb:65`) come
  through automatically because `Member#roles` is a `distinct` association
  over `member_roles` (`app/models/member.rb:23-24`).

Adds exactly one query per summary call (S035).

### Rejected alternatives

- `User#roles_for_project` (used by the prior PR #339 attempt) — is a
  `User`-only method; calling it when `Setting.issue_group_assignment` lets
  `issue.assigned_to` be a `Group` raises `NoMethodError` (confirmed on
  Redmine 7.0.1). It also leaks built-in roles on public projects (S035).
- `principal.is_a?(User) ? principal.roles_for_project(p) : []` — treats
  every group as roleless, contradicting the requirement that group roles be
  included too (S035).
- Per-target `principal.memberships.find_by(project_id:)&.roles` — correct
  but N+1; the bulk `Member.where` gets the same result in one query (S035).
- Loading `Project#members` in full and matching in Ruby — reads unrelated
  rows on large projects; querying by the specific principal IDs is more
  direct (S035).

Archived projects are a known non-target: `Member.where` still returns rows
for them (unlike `User#roles_for_project`, which returns `[]`), but
`issue.visible?` already fails closed with "Permission denied" before
`issue_summary` reaches the role lookup, so the path is unreachable (S035).

## Decision: gate role enrichment on whether instructions are present

`issue_summary` calls `generate_issue_data` (unchanged) when
`issue_summary_instructions` is blank (nil, `""`, or whitespace-only), and
`generate_issue_data_with_roles` only when it is present (S035).

Role data is embedded directly in the issue JSON that goes into the prompt,
so attaching it unconditionally would itself create a prompt diff for
projects that never asked for it — incompatible with the zero-diff decision
on the linked prompt-template page. Roles are meant to be used "when the
additional instructions call for it"; with no instructions there is nothing
for the model to apply them to (S035).

Unconditional attachment (treating the zero-diff requirement as "template
body only," not "full rendered prompt") was considered and rejected as
harder to verify precisely, undercutting the reason zero-diff was required
in the first place (S035).

## Decision: `generate_issue_data_with_roles` stays scoped to the summary path

`generate_issue_data` has five other call sites
(`lib/redmine_ai_helper/tools/vector_tools.rb:92,173,233`,
`lib/redmine_ai_helper/tools/issue_update_tools.rb:93,104,205,222`,
`lib/redmine_ai_helper/tools/issue_tools.rb:33`, and `issue_read_agent.rb`'s
reply-draft/sub-issue/inline-completion call sites). Adding a new method
alongside the existing one, rather than changing `generate_issue_data`
itself, means none of those call sites are touched. The chosen way to keep
this true over time is a test asserting the `generate_issue_data` return
value never contains a `:roles` key (S035).

## Related

- [Issue Summary Instructions: Prompt Template & Settings](./issue-summary-instructions-prompt-template.md) —
  the zero-prompt-diff template split, the setting's name, and cache/pattern
  decisions.
- [Issue AI Features](./issue-ai-features.md) — where `issue_summary` and the
  other `IssueReadAgent` features live.
- [Tool System](./tool-system.md) — `generate_issue_data`'s consumers, kept
  unaffected by this change.
