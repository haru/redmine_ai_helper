---
title: Vector Search Registration Scope
type: component
sources: [S010, S012, S033]
updated: 2026-11-21
---

# Vector Search Registration Scope

Which projects get registered and how. Split from [Vector Search Internals](./vector-search-internals.md).

## Registration scope & project selection

Indexing is limited to projects with the `ai_helper` module enabled (feature
019), and can be narrowed to a chosen set via
`AiHelperSetting#vector_target_projects_relation` (ADR-003) / the
`AiHelperVectorTargetProject` model — preventing data proliferation on
multi-tenant instances (S010).

**Base scope can widen to all projects**: the module-enabled base set above
is `AiHelperSetting#vector_scope_projects` (renamed from
`#ai_helper_module_projects`), which returns all **non-archived** projects
instead (archived projects stay excluded either way) when the admin turns on
the [all-projects data-access scope](./all-projects-data-access-scope.md)
setting — the same setting also applied to `#vector_target?`'s guard. The
"Register all projects" / per-project-selection behavior below then operates
over that widened base set. See [All-Projects Scope: Effects &
Alternatives](./all-projects-scope-effects.md) for the details (S033).

A **"Register all projects" checkbox** (default **ON**; an unset legacy value
counts as ON) controls this (S012):

- **ON** registers every vector-scope project — unchanged legacy behavior
  when `all_projects_scope` is OFF (module-enabled projects only); also
  covers module-disabled projects once `all_projects_scope` is ON (S033).
- **OFF** reveals a multi-select built from `@vector_candidate_projects`
  (`AiHelperSetting#vector_scope_projects`,
  `app/controllers/ai_helper_settings_controller.rb`) — module-enabled
  projects only by default (S012), or every non-archived project once
  `all_projects_scope` is ON (S033); the effective target is always
  **selection ∩ vector-scope**, so a selected-but-out-of-scope project is
  excluded (S012, S033).
- The flag and the selected list persist **independently**: turning the flag
  back ON keeps the selection so it can be restored when toggled OFF again (S012).
- Selection is **per project** — selecting a parent does *not* pull in its
  subprojects (S012).

Changes apply on the **next `regist` run**, not in real time: newly selected
projects get their existing issues/wiki added; deselected projects have their
vector data deleted (the Redmine records themselves stay) (S012). Flag OFF with
nothing selected is a valid 0-target no-op, and any existing data is removed on
the next update (S012).

**Per-project gating**: vector-dependent features (similar-issue search,
duplicate check) work only where vector search resolves to *enabled* — vector
search on **and** (flag ON, or the project is in the selection). Everywhere else
they behave as if vector search were off (S012).

## Related

- [Vector Search Internals](./vector-search-internals.md) — the main page.
