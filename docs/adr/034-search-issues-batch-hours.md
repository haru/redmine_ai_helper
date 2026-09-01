# ADR-034: Batch-load hours for search_issues response

**Date**: 2026-08-30
**Status**: Accepted

## Context

`search_issues` (IssueSearchTools) was changed to include `estimated_hours`, `total_estimated_hours`, `spent_hours`, and `total_spent_hours` in each returned issue (feature 054-mcp-issue-data).

A naive implementation called `issue.spent_hours`, `issue.total_spent_hours`, and `issue.total_estimated_hours` directly on each `Issue` returned by `format_issues`. `Issue#spent_hours` runs `time_entries.sum(:hours)` and `Issue#total_spent_hours`/`#total_estimated_hours` run `self_and_descendants...sum(...)` for non-leaf issues — none of these are covered by the `.includes(:project, :status, :priority, :tracker, :assigned_to, :author, :custom_values)` eager-loading already in place, so each call triggers its own SQL query. This is an N+1 (up to 3 extra queries per issue) proportional to `limit` (default 50, no upper bound), the same class of problem ADR-033 addressed for `list_project_activities` in this same feature.

## Decision

Add `IssueSearchTools#batch_load_issue_hours(issues)`, which computes spent/estimated hours for a whole collection of issues in a small, constant number of queries:

- `spent_hours` for every issue is fetched in one query: `TimeEntry.where(issue_id: issue_ids).group(:issue_id).sum(:hours)`.
- Issues are partitioned into leaf / non-leaf using `Issue#leaf?` (an in-memory check on already-loaded `lft`/`rgt`, no query).
- For leaf issues, `total_spent_hours` equals `spent_hours` and `total_estimated_hours` equals `estimated_hours` — matching `Issue#total_spent_hours`/`#total_estimated_hours`'s own leaf-case shortcut, with no extra query.
- For non-leaf issues (which need to aggregate over descendants), two additional queries cover *all* of them at once, regardless of how many there are: one `Issue.where(root_id: root_ids).pluck(:id, :root_id, :lft, :rgt)` to get nested-set boundaries for every issue in the relevant trees (mirrors `total_spent_hours`, which does not filter by visibility), and one `Issue.visible(User.current).where(root_id: root_ids).pluck(:id, :root_id, :lft, :rgt, :estimated_hours)` for the visibility-filtered estimated-hours sum (mirrors `total_estimated_hours`, which does call `.visible`). Per-issue descendant sets are then computed in memory using the same `root_id`/`lft`/`rgt` containment check `self_and_descendants` uses.

`format_issues` looks up each issue's hours from the resulting hash instead of calling the `Issue` instance methods.

## Consequences

**Positive**:
- Query count for the hours fields is bounded (1 query if all returned issues are leaves, up to 3 if any are not), regardless of how many issues are returned.
- Existing behavior is preserved exactly, including the leaf/non-leaf branching and visibility rules of `Issue#total_estimated_hours`.

**Negative**:
- More code than calling the three `Issue` instance methods directly; the batching logic re-implements `self_and_descendants`'s containment check in Ruby.
- The two non-leaf queries fetch all issues in the relevant root trees (not just descendants of the specific issues in the result set), which is a wider read than the minimal set — a reasonable trade-off since it keeps the query count constant.

## Alternatives Considered

- **Call `issue.spent_hours`/`total_spent_hours`/`total_estimated_hours` directly (original implementation)**: Simplest code but N+1, as described above.
- **`.includes(:time_entries)` only**: Would fix `spent_hours` for leaf issues but not `total_spent_hours`/`total_estimated_hours` for non-leaf issues, which still call `self_and_descendants` (a fresh query) regardless of what's preloaded on the parent.
