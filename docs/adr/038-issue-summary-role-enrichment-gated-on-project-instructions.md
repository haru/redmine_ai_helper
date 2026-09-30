# ADR-038: Issue-Summary Role Enrichment Is Gated on Project Instructions and Resolved Through Memberships Only

**Date**: 2026-09-20
**Status**: Accepted (supersedes the role-resolution approach of PR #339)

## Context

Feature 058 adds per-project instructions for the issue AI summary (`issue_summary_instructions`), and lets those instructions reference the project roles of the issue's author, assignee and comment authors. Two constraints from the specification shaped how role information may be obtained and attached:

1. **Byte-identical legacy prompt (FR-007 / SC-003).** For a project without summary instructions, the prompt sent to the model must be exactly the pre-feature prompt — zero character difference, provable by a single `assert_equal`.
2. **Built-in roles must never leak (FR-015).** Redmine's synthetic roles `Non member` and `Anonymous` describe a permission fallback, not a membership; attaching them as "roles" would invite the model to reason from them.

PR #339 (unmerged) attempted role enrichment by calling `User#roles_for_project` while building the summary. That approach fails both constraints and has a hard defect: `roles_for_project` is defined on `User` only (`app/models/user.rb`), so an issue assigned to a **Group** — possible since Redmine 3.x with `Setting.issue_group_assignment` — raises `NoMethodError` and the summary fails. It also returns the built-in roles for public projects (`project.override_roles(builtin_role)`), violating FR-015 for every non-member participant.

## Decision

**Role enrichment for the issue summary is produced exclusively by `RedmineAiHelper::Util::IssueJson#generate_issue_data_with_roles`, and every role it reports is resolved through membership records fetched in one bulk `Member` query. Roles are attached only when the project has summary instructions.**

Two sub-decisions implement this:

1. **Resolution path: `Member`, not `User#roles_for_project`.** `Member#user_id` holds a Principal id (Redmine maps `Principal has_many :members, foreign_key: 'user_id'`), so Users and Groups are resolved by the same query — which removes the `NoMethodError` class of failure structurally rather than patching around it. Roles come from `member.roles` (the `member_roles` join, `distinct`), so group-inherited roles — which Redmine materialises as `MemberRole#inherited_from` rows on the user's own membership — are included with no extra code, and built-in roles can never appear because only membership rows are consulted. The private helper `project_role_names_by_principal_id` issues one bulk `Member.where(project_id:, user_id: ids).includes(:roles)` per summary — a fixed set of three SQL statements (members → member_roles → roles), independent of the number of participants — keeps result names sorted and de-duplicated, omits principals without a membership (the caller defaults them to `[]`), and skips the query entirely when no principals are involved.

2. **Gating: no instructions, no roles.** `IssueReadAgent#issue_summary` uses `generate_issue_data_with_roles` only when the project's `issue_summary_instructions` is present; otherwise it uses the unchanged `generate_issue_data`. Because roles travel inside the issue JSON embedded in the prompt, unconditional attachment would break the byte-identical guarantee; gating keeps SC-003 verifiable by direct string equality. The role-bearing representation is used by no other caller — `generate_issue_data` (which represents people as bare `{id, name}` records) remains the shared shape for reply drafts, sub-issue drafts, vector search and the update tools, enforced by a regression test asserting its JSON never contains a `roles` key.

## Consequences

- Group assignees, non-member groups, unset assignees, non-member users and anonymous users are all non-raising paths by construction; tests pin each case.
- The extra cost per summary is a fixed set of three SQL statements (members → member_roles → roles, via `includes(:roles)` preloading), independent of the number of participants.
- `summary.yml` / `summary_ja.yml` stay byte-identical; the additional-instructions section lives in separate templates (`summary_instructions{,_ja}.yml`) concatenated Ruby-side only when instructions exist.
- The plugin does not interpret role names (FR-011): they are passed through verbatim, and the prompt template tells the model to treat their meaning as defined by the instructions, not to guess it.
- PR #339's use case is covered without `User#roles_for_project`; the PR is superseded by this design.

## Alternatives Considered

- **`User#roles_for_project` (PR #339's approach).** Rejected. The method is defined on `User` only, so an issue assigned to a Group raises `NoMethodError` and the summary fails; and for public projects it returns the built-in `Non member` role, violating FR-015 for every non-member participant.
- **Attaching roles unconditionally.** Rejected. Roles travel inside the issue JSON embedded in the prompt, so unconditional attachment would change the prompt for projects without instructions and destroy the byte-identical legacy-prompt guarantee (FR-007 / SC-003).
- **Adding `roles` to the shared `generate_issue_data`.** Rejected. The shared shape feeds reply drafts, sub-issue drafts, vector search and the update tools, and its output must not change (FR-010a / SC-004b). `VectorTools` output is persisted to the vector store, so a leak there would be durable rather than transient.
