# ADR-033: Batch-load projects for list_project_activities response

**Date**: 2026-08-30
**Status**: Accepted

## Context

`list_project_activities` (ProjectTools) returns activity events from `Redmine::Activity::Fetcher`. Each event needs a `project: {id, name}` field in the response (feature 054-mcp-issue-data).

A naive implementation would call `event.project` for every event and pass it to `format_named_record`. However, not all activity provider models preload `:project` in their `acts_as_activity_provider` scope. Models like `TimeEntry`, `Changeset`, and `WikiContentVersion` do not include `:project` in their preload scope, so calling `event.project` on each triggers a lazy-loaded query — an N+1 proportional to the number of returned activities (up to `limit`, default 100).

## Decision

Collect project IDs from all events using the existing `event_project_id` helper (which reads the `project_id` foreign-key column directly when available, avoiding association loads), then batch-load all needed projects with a single `Project.where(id: project_ids).index_by(&:id)` query. Each event's `project` field is resolved from this in-memory hash.

## Consequences

**Positive**:
- At most 1 additional SQL query for project data regardless of activity count.
- Reuses the existing `event_project_id` helper which already optimizes ID extraction.
- Consistent `{id, name}` format via `format_named_record`, also added to `BaseTools` in the same feature (`IssueJson#format_named_record` keeps its own copy since that module is included by non-`BaseTools` classes such as `IssueReadAgent`).

**Negative**:
- Slightly more code than `format_named_record(event.project)`.
- Events whose `event_project_id` returns `nil` will have a `nil` project field (acceptable — this was also the case before this feature).

## Alternatives Considered

- **`format_named_record(event.project)` per event**: Simplest code but causes N+1 for models that don't preload `:project`. Given that the feature's goal is to reduce AI client round-trips, introducing an N+1 in the response construction is counterproductive.
- **Modify Redmine core activity provider scopes to preload `:project`**: Would fix the root cause but is outside the plugin's responsibility (same reasoning as ADR-029/ADR-030).
