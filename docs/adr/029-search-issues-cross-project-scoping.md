# ADR-029: search_issues Cross-Project Scoping

**Date**: 2026-08-24
**Status**: Accepted

## Context

`search_issues` required `project_id`, which made it impossible to answer cross-project questions such as "which issues are assigned to me." Making `project_id` optional required deciding how to determine the set of projects a cross-project search may draw issues from.

An earlier community contribution (PR #376, discarded — see spec.md Assumptions) attempted this by relying solely on `Issue.visible(User.current)` when `project_id` was omitted. The plugin maintainer rejected that approach during review:

> This change would make issues from projects where AI Helper is not enabled part of the search results, which goes against this plugin's policy. Some projects do not want their information sent to an LLM, so issues from projects without AI Helper enabled must be excluded from the search.

`Issue.visible` only enforces Redmine's standard `:view_issues` permission; it has no awareness of whether the `ai_helper` module is enabled for a project. Every other read path in this plugin (`accessible_project?` in `base_tools.rb`) treats "AI Helper module enabled + `:view_ai_helper` permission granted" as a mandatory gate before any project data reaches the LLM. A cross-project search that skipped this gate would silently leak issues from projects that opted out of AI Helper.

The PR thread converged on a fix, proposed by the contributor and accepted by the maintainer:

```ruby
scope = Issue.visible(User.current).open
if project_id
  scope = scope.where(project_id: project_id)
else
  scope = scope.joins(:project).where(Project.allowed_to_condition(User.current, :view_ai_helper))
end
```

`Project.allowed_to_condition(user, :view_ai_helper)` (Redmine core, `app/models/project.rb`) builds a single SQL condition that already encodes: project active status, an `EXISTS` check against `enabled_modules` for the module the permission belongs to (`ai_helper`, since `:view_ai_helper` is declared inside `project_module :ai_helper` in `init.rb`), and role-based permission grant (covering both public/non-member access and membership-based access). This is the SQL-level equivalent of `accessible_project?`, without loading every project into Ruby to test it one at a time.

## Decision

When `project_id` is omitted, `search_issues` scopes the query to projects satisfying `Project.allowed_to_condition(User.current, :view_ai_helper)`, combined with the existing `Issue.visible(User.current)` check. This applies to both the no-filter (open issues) path and the `IssueQueryBuilder` filter path (added to `@query.base_scope`, which already joins `projects`).

When `project_id` is given, the existing single-project path (`@query.project = project`, `accessible_project?` guard) is left untouched — it is not reimplemented in terms of `allowed_to_condition`.

The full PR #376 diff (including its "no module check" no-condition case) is not reused; only the scoping technique agreed upon in its review discussion is.

## Consequences

- **Positive**: Cross-project search cannot return issues from projects that have not opted into AI Helper, closing the gap PR #376's initial version left open.
- **Positive**: Scoping is a single SQL condition (`EXISTS` + `IN`/`OR` over role-assigned project IDs), not an N-project Ruby-side permission check, so cost does not grow linearly with the number of projects in Ruby-land.
- **Positive**: When the current user has no `:view_ai_helper`-granted role anywhere, `Project.allowed_to_condition` returns the literal condition `"1=0"`, so the search naturally returns zero results without needing an explicit empty-project-list branch.
- **Negative**: The single-project and cross-project paths now use two different mechanisms to reach an equivalent guarantee (`accessible_project?` in Ruby vs. `Project.allowed_to_condition` in SQL). This is intentional — see Alternatives Considered — but means a future reader must understand both instead of one.

## Alternatives Considered

- **Reuse `Project.all.select { |p| accessible_project?(p) }.map(&:id)`** (the pattern already used by `list_projects` in `project_tools.rb`) and pass the resulting ID array as an `IN` filter: works, but loads and checks every project row in Ruby on every cross-project search. Rejected in favor of the SQL condition agreed upon in the PR #376 review.
- **Ship PR #376 as originally written** (`Issue.visible` only, no module-enabled check): rejected by the maintainer during that PR's review — it would leak issues from AI-Helper-disabled projects to the LLM, violating this plugin's core data-handling policy.
- **Unify the single-project and cross-project paths** by always leaving `@query.project` nil and using an explicit `project_id` filter or `Project.allowed_to_condition` even when `project_id` is given: rejected because `@query.project` being set also affects unrelated `IssueQuery` behavior (subproject inclusion via `Setting.display_subprojects_issues?`, `category_id` filter availability, `rolled_up_custom_fields` vs. all custom fields — see spec.md FR-005 and this feature's research.md R2). Touching the single-project path risked changing its existing, already-relied-upon behavior for no benefit.
