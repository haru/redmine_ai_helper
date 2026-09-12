---
title: "All-Projects Scope: Effects & Alternatives"
type: decision
sources: [S033, S034]
updated: 2026-09-12
---

# All-Projects Scope: Effects & Alternatives

Second half of [All-Projects Data-Access Scope](./all-projects-data-access-scope.md)
— the widened `all_projects_scope` admin setting's effect on vector
registration, what it deliberately leaves untouched, and the alternatives
rejected (S033).

## Vector registration scope (FR-016/FR-017)

`AiHelperSetting#ai_helper_module_projects` is renamed to
`#vector_scope_projects`: when `all_projects_scope` is ON it returns every
project in a registerable status (`VECTOR_SCOPE_PROJECT_STATUSES` — active and
closed; **archived and scheduled-for-deletion projects are excluded**, because
`Project.visible_condition` denies them at query time so their embeddings could
never be retrieved), or the previous module-enabled-projects scope when OFF.
`#vector_target?` applies the same status gate and its module guard becomes
`all_projects_scope || project.module_enabled?(:ai_helper)`. See [Vector Search
Internals](./vector-search-internals.md) (S033).

The admin settings controller adds a separate `@vector_candidate_projects`
for the vector tab; the **channel tab's** `@ai_helper_projects` (which
projects can bind to a chat gateway channel) stays module-scoped-only and
untouched — binding a chat channel to a module-disabled project is out of
scope for this feature (S033).

## What explicitly does not change

- **UI display gating** — `PermissionChecker.module_enabled?`, view hooks,
  `projects_helper_patch.rb`, `projects_queries_helper_patch.rb`: the AI
  Helper icon/menu still only appears on module-enabled projects (S033).
- **Chat gateway entry point** — `chat_channel/message_handler.rb`'s
  module-enabled check is unchanged; a channel bound to a module-disabled
  project still gets the "module not enabled" reply regardless of this
  setting (S033).
- ~~**Tools with no module gate already** (`issue_tools.rb`, `wiki_tools.rb`,
  `board_tools.rb`, `version_tools.rb`, `repository_tools.rb`,
  `file_tools.rb`) — these already check only Redmine's standard `visible?`;
  no new gate is added to them (YAGNI) (S033).~~ **Withdrawn.** Checking only
  Redmine's `visible?` is precisely what let AI Helper summarize an issue from
  a module-disabled project with the setting OFF, and the premise was false
  for `repository_tools.rb`, which checked nothing at all. All six now call
  `accessible_project?`, and the repository tools additionally enforce
  Redmine's own `:browse_repository` / `:view_changesets`. See
  [Tool System](./tool-system.md) and ADR-037 (S034).
- **Read-only mode interaction** — needs no new code: mutating tools are
  already excluded by the existing `write: true` filter (see [Tool
  System](./tool-system.md)) independently of project scope, so the two
  settings compose without extra logic (S033).
- **MCP server endpoint** — because it calls the same `BaseTools` subclasses,
  the eight-site replacement applies automatically to MCP-driven requests
  too, with no separate change (S033). See [MCP
  Integration](./mcp-integration.md).

## Rejected alternatives

- **Branch directly in `BaseTools#accessible_project?`**: doesn't cover
  `IssueReadAgent` (doesn't include `BaseTools`), `VectorTools`'s
  post-retrieval filters, or the SQL conditions — duplication would remain
  (S033).
- **Loosen the module-enabled path too** (ignore `view_ai_helper` whenever
  the setting is ON): rejected — silently defeats an admin's existing role
  configuration; exceeds what the clarified requirement asked for (S033).
- **Load all visible project IDs into Ruby and pass as an `IN` clause**:
  rejected for the same reason [ADR-030](../../docs/adr/030-list-project-activities-cross-project-scoping.md)-adjacent
  decisions reject it — avoid loading the full project set into memory when a
  SQL condition suffices (S033).
- **Request-level memoization of the setting flag**: would conflict with the
  requirement that toggling the setting take effect immediately, no restart
  needed; out of scope (YAGNI) (S033).

Recorded as ADR-036 (planned; not yet merged as of this ingest) (S033).

## Related

- [All-Projects Data-Access Scope](./all-projects-data-access-scope.md) —
  the setting, centralized methods, and judgment table (first half).
- [Vector Search Internals](./vector-search-internals.md) — the registration
  scope this feature widens.
- [MCP Integration](./mcp-integration.md) — why the endpoint needed no
  separate change.
