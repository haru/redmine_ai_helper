---
title: search_issues Cross-Project Scoping
type: decision
sources: [S026]
updated: 2026-08-24
---

# search_issues Cross-Project Scoping

`search_issues` (`IssueSearchTools`, part of the [Tool System](./tool-system.md))
originally required `project_id`, which made cross-project questions like
"which issues are assigned to me" impossible to answer in one call. An earlier
community contribution (PR #376) tried making `project_id` optional by relying
solely on `Issue.visible(User.current)` for the no-project case. The
maintainer rejected that version during review: it would let issues from
projects that never enabled the `ai_helper` module leak into search results
(S026).

## Decision

`project_id` is optional (`required: false`). When omitted, both search paths
scope to projects satisfying `Project.allowed_to_condition(User.current,
:view_ai_helper)`, combined with the existing `Issue.visible(User.current)`
check — the SQL-level equivalent of the `accessible_project?` guard used when
`project_id` **is** given (S026):

```ruby
scope = Issue.visible(User.current).open
if project_id
  scope = scope.where(project_id: project_id)
else
  scope = scope.joins(:project).where(Project.allowed_to_condition(User.current, :view_ai_helper))
end
```

- **No-filter path**: `Issue.visible(User.current).open` already includes
  `joins(:project)`, so the `allowed_to_condition` SQL fragment attaches
  directly via `.where` (S026).
- **Filter path (`IssueQueryBuilder`)**: `@query.base_scope` already joins
  `projects`, so a private `cross_project_scope` helper adds the same
  `.where` condition in both `execute` and `count`, only when `project` is
  `nil` (S026).
- **`project_id`-given path is untouched**: `@query.project = project` and
  the `accessible_project?` guard keep working exactly as before — the two
  paths intentionally use different mechanisms (Ruby-side `accessible_project?`
  vs. SQL-side `allowed_to_condition`) to reach the same guarantee, because
  unifying them by always leaving `@query.project` nil would change
  `IssueQuery`'s implicit behavior (subproject inclusion via
  `Setting.display_subprojects_issues?`, `category_id` filter availability,
  `rolled_up_custom_fields` vs. all custom fields) for the single-project
  case (S026).
- **Zero accessible projects**: no explicit empty-list branch exists.
  `Project.allowed_to_condition` returns the literal `"1=0"` when the current
  user holds no role with `:view_ai_helper` anywhere, so the query naturally
  returns zero results without raising (S026).
- **`project_id: nil` is a valid input, not a missing-required-param error**:
  the tool's `nil`-check guideline (raise for essential params) doesn't apply
  here — `project_id` became genuinely optional, so the prior
  `raise "project_id is required" if project_id.nil?` was removed (S026).

Recorded as [ADR-029](../../docs/adr/029-search-issues-cross-project-scoping.md).

## Rejected alternatives

- **`Project.all.select { |p| accessible_project?(p) }.map(&:id)`** (the
  pattern `list_projects` in `ProjectTools` already uses), passed as an `IN`
  filter: works, but checks every project row in Ruby on every cross-project
  search instead of one SQL `EXISTS` (S026).
- **PR #376 as originally written** (`Issue.visible` only, no
  module-enabled check): rejected by the maintainer — leaks issues from
  AI-Helper-disabled projects to the LLM (S026).
- **Unify both paths** by always leaving `@query.project` nil and filtering
  by `project_id`/`allowed_to_condition` even when a project is given:
  rejected — touching the single-project path risked changing its
  already-relied-upon `IssueQuery` behavior for no benefit (S026).

## Related

- [Tool System](./tool-system.md) — `accessible_project?`, the DSL's
  `required:` flag, and where this tool provider sits.
