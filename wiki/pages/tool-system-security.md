---
title: Tool System Security & Read-Only Mode
type: component
sources: [S008, S016, S026, S033, S034]
updated: 2026-11-21
---

# Tool System Security & Read-Only Mode

Per-tool permission checks, read-only filtering and write safety. Split from [Tool System](./tool-system.md).

## Security & read-only

- **Read checks**: read tools validate access with Redmine's own visibility
  (`issue.visible?`, `board.visible?`, …) **and** `accessible_project?` — both,
  never one instead of the other, since Redmine's `visible?` says nothing about
  whether the project opted into AI Helper (S008, S034). A tool's project scope can also be made
  *optional*: `IssueSearchTools#search_issues`'s `project_id` is
  `required: false`, and when omitted it scopes to
  `Project.allowed_to_condition(user, :view_ai_helper)` instead of a single
  project's `accessible_project?` check — see
  [search_issues Cross-Project Scoping](./search-issues-cross-project-scoping.md) (S026).
- **Data-access scope is centralized**: `accessible_project?` and the
  cross-project SQL condition above both delegate to
  `RedmineAiHelper::Util::PermissionChecker#data_accessible?` /
  `#data_access_condition`, which fold in the optional **all-projects
  data-access scope** admin setting — module-disabled projects can be
  included via standard Redmine permissions when an admin opts in. See [All-Projects
  Data-Access Scope](./all-projects-data-access-scope.md) (S033).
- **Write checks**: write tools call `accessible_project?` first, then
  `User.current.allowed_to?(:action, project)` — a project outside the
  data-access scope must not be written to either (S008, S034).
- **Repository tools**: `RepositoryTools` enforces Redmine's own repository
  permissions the way Redmine maps them — `:browse_repository` for repository
  info, file info, file contents and diffs, `:view_changesets` for revision
  info — on top of `accessible_project?` (S034).
- **Read-only mode**: because each mutating tool is tagged `write: true`, global
  read-only mode can filter those individual tools out (S008). This is why
  *internal* tools can be selectively disabled, whereas external
  [MCP](./mcp-integration.md) agents — whose tools carry no such flag — are
  disabled wholesale.
- **Atomic writes**: `IssueUpdateTools` wraps changes in `Issue.transaction` so
  relations and custom fields persist consistently (S008).
- **`write_tool?` reused for step-level routing safety**: `BaseAgent#can_write?`
  (`available_tool_classes.any?(&:write_tool?)`) reuses this same flag to guard
  which agent a write-requiring plan step may be dispatched to — an internal
  check, never exposed to the LLM. See
  [Agent Write-Capability Routing](./agent-write-capability-routing.md) (S016).
- **`validate_only`**: a parameter that runs schema validation without
  persisting — an LLM pre-check before an actual write (S008).
- **VectorTools dual filtering**: results are filtered first by Qdrant metadata,
  then again post-retrieval by visibility/permission, preventing leakage (S008).
  See [Vector Search](./vector-search.md).

## Related

- [Tool System](./tool-system.md) — the main page.
