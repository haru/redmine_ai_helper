---
title: All-Projects Data-Access Scope
type: decision
sources: [S033, S034]
updated: 2026-09-12
---

# All-Projects Data-Access Scope

A per-instance admin setting, `all_projects_scope` (boolean column on
`ai_helper_settings`, `default: false`), that lets AI Helper read and update
data in projects where the `ai_helper` module is **not** enabled, using only
Redmine's standard permissions — instead of the historical
module-enabled-only rule (S033). Part of the
[Tool System](./tool-system.md)'s access-control story.

## Problem

Before this feature, eight call sites across the codebase independently
re-implemented the same "module enabled + `view_ai_helper`" data-access check
(`base_tools.rb#accessible_project?`/`#accessible_projects`,
`issue_search_tools.rb` ×2 SQL conditions, `vector_tools.rb` ×2 Ruby filters,
`issue_read_agent.rb#fetch_todo_issues_from_other_projects`) — a DRY
violation the project's constitution flags at 3+ duplicates (S033).

## Decision

Centralize the judgment in `RedmineAiHelper::Util::PermissionChecker` as two
methods, both defaulting `all_projects_scope:` to
`AiHelperSetting.all_projects_scope?` (S033):

```ruby
# Ruby predicate — single project / post-retrieval result filtering
def self.data_accessible?(project:, user: User.current,
                           all_projects_scope: AiHelperSetting.all_projects_scope?)
  return false unless project&.id && project.visible?(user)
  return user.allowed_to?(:view_ai_helper, project) if project.module_enabled?(:ai_helper)
  all_projects_scope
end

# SQL condition — cross-project search. Caller's relation must already
# scope data-type visibility (e.g. Issue.visible).
def self.data_access_condition(user = User.current,
                                all_projects_scope: AiHelperSetting.all_projects_scope?)
  condition = Project.allowed_to_condition(user, :view_ai_helper)
  return condition unless all_projects_scope
  "((#{condition}) OR NOT EXISTS (SELECT 1 FROM #{EnabledModule.table_name} em" \
    " WHERE em.project_id = #{Project.table_name}.id AND em.name = 'ai_helper'))"
end
```

All eight sites, plus [`search_issues`'s cross-project
path](./search-issues-cross-project-scoping.md), now delegate to these two
methods (S033).

Every remaining data-reaching tool was added to that set afterwards — the
issue, wiki, board, version, file, repository and issue-write tools, which
this feature had originally left checking only Redmine's own `visible?`. See
[All-Projects Scope: Effects & Alternatives](./all-projects-scope-effects.md)
for what that omission caused and
[Tool System](./tool-system.md) for the per-tool checks (S034).

### Resulting judgment table

| Project's `ai_helper` module | Setting OFF (default) | Setting ON |
|---|---|---|
| Enabled | `visible?` && `allowed_to?(:view_ai_helper)` (unchanged) | same as OFF (unchanged) |
| Disabled | excluded (unchanged) | `visible?` only — standard Redmine permission |

With the setting OFF, `data_accessible?` and `data_access_condition` reduce
to exactly the pre-existing expressions, so default behavior is provably
unchanged (S033).

### The asymmetry is intentional

Turning the setting ON does **not** relax the check for module-*enabled*
projects — `view_ai_helper` is still required there. The clarified
requirement only concerned module-*disabled* projects; loosening the
module-enabled path too would silently override an admin who removed
`view_ai_helper` from a role specifically to keep that role away from AI
Helper, which the setting was never asked to undo (S033).

### Performance

Loop-based callers (`accessible_projects`, `vector_tools.rb`'s
`collect_permitted_project_ids`, `fetch_todo_issues_from_other_projects`)
read the flag **once** and pass it through via the `all_projects_scope:`
keyword, so the settings row isn't re-queried per project — preserving the
constant-query-count property [ADR-030](../../docs/adr/030-list-project-activities-cross-project-scoping.md)
established for similar loops (S033).

### `data_access_condition` callers must already scope visibility

The SQL condition alone does not check row visibility — both current callers
build on `Issue.visible(user)` (itself
`Project.allowed_to_condition(user, :view_issues)`), which already handles
project state/visibility; `data_accessible?`'s willingness to include closed
projects is consistent with that (S033).

This page continues in [All-Projects Scope: Effects &
Alternatives](./all-projects-scope-effects.md), which covers the vector
registration scope change, what explicitly does **not** change, and rejected
alternatives.

## Related

- [Tool System](./tool-system.md) — the DSL and read/write check story this
  setting slots into.
- [search_issues Cross-Project Scoping](./search-issues-cross-project-scoping.md) —
  the SQL condition this feature extends.
- [All-Projects Scope: Effects & Alternatives](./all-projects-scope-effects.md) —
  the second half of this decision.
