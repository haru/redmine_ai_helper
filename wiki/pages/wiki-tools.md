---
title: Wiki Tools
type: component
sources: [S032]
updated: 2026-09-01
---

# Wiki Tools

`RedmineAiHelper::Tools::WikiTools` (read) and `WikiWriteTools` (write) are the
[Tool System](./tool-system.md) providers registered on `wiki_agent`. Both
share one serializer, `RedmineAiHelper::Util::WikiJson#generate_wiki_data`, for
turning a `WikiPage` into the JSON handed to the LLM (S032).

## Parent page output format

Every tool that returns page data — `read_wiki_page`, `wiki_add_page`,
`wiki_update_page` (all via `generate_wiki_data`) and `list_wiki_pages`
(built independently) — reports the parent page the same way:

```json
"parent": { "id": 12, "title": "Parent Page" }   // or null for a top-level page
```

This is a non-breaking extension: the `title` key already existed, `id` was
added alongside it. `list_wiki_pages` additionally gained its own `id` field
per element, so a flat page list can be reassembled into a tree client-side
without a second lookup (S032).

## `wiki_update_page`'s `parent_title` parameter

`parent_title` (optional, string) reparents an existing page in the same
transaction as its `content`/`new_title` update — one failure rolls back the
whole change:

- **omitted** (`nil`) — parent is left untouched.
- **empty string** (`""`) — the page is detached and becomes top-level.
- **non-empty string** — the page's own wiki is searched for a page with that
  title (`wiki.find_page(parent_title)`) and, if found and valid, becomes the
  new parent.

Validation is done with explicit checks and `raise` — the same style
`wiki_add_page` already used — rather than by setting `page.parent_title=`
and inspecting `page.errors`. The rejected alternative would have been
shorter, but its error text comes from Rails i18n defaults (e.g. "Parent
page is invalid") instead of the project's own specific, English `raise`
messages, breaking consistency with the rest of `WikiWriteTools` (S032):

| Condition | Error |
|---|---|
| No page with that title in this wiki | `"Parent page not found: title = {parent_title}"` |
| Target is the page itself or one of its own descendants | `"Cannot set parent page: circular reference detected (title = {parent_title})"` |
| Save fails after validation passes | `"Failed to update wiki page parent: {validation errors}"` |

No new permission category was introduced — these checks run inside the
same `:edit_wiki_pages` + ai_helper-module-enabled gate `wiki_update_page`
already enforced (S032).

## Cross-wiki parents are rejected implicitly

`Wiki#find_page` only searches that wiki's own `pages` association, so a
`parent_title` naming a page in a *different* project's wiki simply doesn't
match — it surfaces as the ordinary "Parent page not found" error. No
separate same-project check was added; Redmine core's `not_same_project`
validation was deliberately not called from here (S032).

## Circular-reference check reuses `acts_as_tree`

Redmine core's `WikiPage` already provides `parent`/`children`/`ancestors`
via `acts_as_tree` (no new gem). A candidate parent is rejected when it
equals the target page or when `candidate.ancestors.include?(target)` —
i.e. the candidate is a descendant of the page being reparented (S032).

## No N+1 optimization added for `parent`

`list_wiki_pages` now dereferences `page.parent` for every page returned,
each a lazy-loaded `belongs_to` lookup (at most one query per page with a
parent). No `includes(:parent)` eager-load was added: the existing
`list_wiki_pages` already has the same shape of N+1 through
`page.content.author`, and matching that existing pattern was preferred over
a one-off optimization (S032).

## No new migration

Everything here reuses the existing `wiki_pages.parent_id` column and
`acts_as_tree` relations — no schema change (S032).

## Related

- [Tool System](./tool-system.md) — the `BaseTools` DSL and `write:` tagging
  these providers use.
- [Agent Write-Capability Routing](./agent-write-capability-routing.md) —
  how `WikiWriteTools`' `write_tool?` flag feeds `wiki_agent`'s
  `can_write?`.
