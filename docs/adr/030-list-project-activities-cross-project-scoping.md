# ADR-030: list_project_activities Cross-Project Scoping

**Date**: 2026-08-24
**Status**: Accepted

## Context

`search_issues` (ADR-029) made `project_id` optional by adding `Project.allowed_to_condition(User.current, :view_ai_helper)` as a SQL `where` clause on top of `Issue.visible`. `list_project_activities` needed the same "omit `project_id` to search across all AI-Helper-enabled, accessible projects" capability, so the natural first instinct was to reuse that SQL technique.

That technique only works because `search_issues` queries a single `ActiveRecord::Relation` of `Issue`. `list_project_activities` is built on `Redmine::Activity::Fetcher#events`, which iterates every registered `acts_as_activity_provider` model (`Issue`, `Journal`, `News`, `Message`, `WikiContentVersion`, `Changeset`, `Attachment`, `Document`, etc.), calls each provider's own `find_events` (each with its own scope, its own permission, e.g. `:view_documents`, `:view_news`), and returns the results merged into a single **Ruby array** of heterogeneous model instances. There is no single `ActiveRecord::Relation` to attach a `where` clause to — the array is already materialized by the time `Fetcher#events` returns it, and its elements do not share a common table.

`Fetcher#event_types` also only filters by permission when a `project` is given (`if @project` in `lib/redmine/activity/fetcher.rb`); when `project` is `nil`, every registered event type is included with no additional per-project gate. `Fetcher` and each provider's `find_events` still enforce their own per-model view permission (e.g. `Issue.visible`, `Document.visible`), but none of them know about the `ai_helper` module — the same gap ADR-029 closed for `search_issues`, and one this plugin's `accessible_project?` (`base_tools.rb`) exists specifically to close for every other tool.

## Decision

When `project_id` is omitted, `list_project_activities` fetches events unscoped (`Fetcher.new(current_user, project: nil, author: author)`), then filters the resulting Ruby array in memory:

```ruby
accessible_project_ids = Project.all.select { |p| accessible_project? p }.map(&:id)
events = events.select { |event| accessible_project_ids.include?(event.project&.id) }
```

This is the same pattern `list_projects` already uses (`Project.all.select { |p| accessible_project? p }`), reused rather than reimplemented. It runs after `fetcher.events` and before the existing `sort_by(&:event_datetime).reverse.first(limit)`, so `limit` is applied to the already-filtered set.

When `project_id` is given, the existing single-project path (`Fetcher.new(project: project, ...)`, `accessible_project?` guard) is left untouched.

## Consequences

- **Positive**: Cross-project activity listing cannot include activities from AI-Helper-disabled or inaccessible projects, matching the guarantee `accessible_project?` already provides for every single-project tool call.
- **Positive**: No new judgment logic — the filter is the same `accessible_project?` check and `Array#select` pattern already used by `list_projects`.
- **Negative**: `Project.all.select { |p| accessible_project? p }` evaluates every project in Ruby on every cross-project call (same cost `list_projects` already accepts), rather than a single SQL condition. This mirrors the "Alternatives Considered" tradeoff in ADR-029, but here it is the primary approach rather than the rejected alternative, because the SQL-`where` approach ADR-029 chose is not available: `Fetcher#events` returns a plain Ruby array of mixed model types with no shared relation to attach a `where` clause to.

## Alternatives Considered

- **Reuse ADR-029's SQL `where` technique** (`Project.allowed_to_condition`) by joining it into each provider's scope before calling `find_events`: not applicable here without changing `Redmine::Activity::Fetcher` or every `acts_as_activity_provider` model's scope, since none of them are queried through `list_project_activities`'s own relation — `Fetcher` owns that lookup and already returns a materialized array by the time control returns to this tool. Rejected as out of scope for this feature (`plan.md`: no new classes, no core changes).
- **Filter by event type of provider's own `:permission` before calling `find_events`**: `Fetcher#event_types` already does this, but only when a `project` is present; extending it to also intersect with `ai_helper`-enabled projects when `project` is `nil` would require patching `Redmine::Activity::Fetcher` itself (a Redmine core class), which this plugin does not modify. Rejected for the same reason as above.
