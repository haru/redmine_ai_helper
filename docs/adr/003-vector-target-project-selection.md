# ADR-003: Select which projects are registered in the vector database

**Date**: 2026-06-26
**Status**: Proposed

## Context

[ADR-002](002-vector-scope-by-ai-helper-module.md) scoped vector registration to projects with the `ai_helper` module enabled. That gate is all-or-nothing: every module-enabled project is registered. Site administrators running large instances asked for finer control — they want to enable AI Helper (the chat, summaries, etc.) on many projects while registering only a chosen subset in the vector database, to bound embedding cost and keep similarity search focused.

Two design questions had to be resolved:

1. **Where to persist the selection.** The global vector settings live in the single-row `AiHelperSetting`. The selection is a set of project ids, with a "register everything" escape hatch that must remain the default so existing installations behave exactly as before (SC-002).
2. **How the registration write path, the deletion/cleanup path, and the per-project feature gating stay consistent.** ADR-002 already established that the write path (`vector:regist`) and the cleanup path (`data_in_scope?`) must agree, otherwise data is registered and immediately deleted (or vice versa). Adding a selection dimension multiplies the ways these can diverge.

## Decision

1. **Flag + join table.** Add a boolean `vector_register_all_projects` to `ai_helper_settings` (NOT NULL, default `true`) and a join table `ai_helper_vector_target_projects` (`ai_helper_setting_id`, `project_id`, unique index on the pair, both foreign keys `on_delete: :cascade`). The selection is modeled as `AiHelperSetting has_many :vector_target_projects, through:`. The default `true` preserves ADR-002 behavior for every existing row.

2. **Single source of truth in `AiHelperSetting`.** The registration set is computed by one method, `vector_target_projects_relation`, layered on top of the ADR-002 module scope:
   - `register_all == true` → all `ai_helper`-module projects.
   - `register_all == false` → the intersection of the selection and the module-enabled projects.
   - `register_all == false` with an empty selection → the empty set (no projects, no error — FR-014).

   Both the registration rake task and the per-row `vector_target?(project)` predicate (used by `data_in_scope?`) derive from this method, so the write path and the cleanup path cannot diverge. This is the DRY successor to ADR-002's "compute the set once" rule.

3. **Selection is preserved across the flag.** Turning the flag back ON does **not** discard the selected ids; they remain in the join table and are simply not consulted while the flag is ON (FR-006). In the settings UI the project checkboxes are *hidden but not disabled* when the flag is ON, so the browser still submits them and the selection round-trips without extra hidden-field bookkeeping.

4. **Per-project feature gating.** A new class method `AiHelperSetting.vector_search_enabled_for?(project)` returns `false` when global vector search is off, `true` for any project when `register_all` is ON, and otherwise `vector_target?(project)`. Vector-dependent features — `IssueAgent` (similar-issue search and tool exposure), `WikiAgent` (vector tool exposure), and `AssignmentSuggestion#suggest_from_history` — gate on this instead of the global `vector_search_enabled?`, so they behave as "vector disabled" in projects outside the registration scope (FR-012 / FR-013).

5. **Convergence is batch-only.** As in ADR-002, changing the selection does not touch Qdrant until the next `vector:regist` run: newly selected projects' existing issues/wiki are backfilled, and de-selected projects' vectors are removed by the cleanup pass because `data_in_scope?` now also requires `vector_target?` (FR-010 / FR-011). The Redmine issues/wiki themselves are untouched.

## Consequences

**Positive**:

- Administrators can bound embedding cost and search scope without disabling AI Helper features wholesale.
- Write, cleanup, and feature-gating all read the same `AiHelperSetting` methods, so they stay consistent by construction.
- Default `true` means zero behavior change on upgrade (SC-002).
- Foreign keys with `on_delete: :cascade` keep the join table free of dangling rows when a project or the settings row is deleted; no `Project` patch or manual cleanup is needed.

**Negative / trade-offs**:

- One new table and one new column (ADR-002 deliberately avoided migrations; this feature requires persistence and accepts that cost).
- Scope changes are not reflected in Qdrant until the next batch run — an operator who de-selects a project still has its vectors searchable until `vector:regist` runs. This matches the existing ADR-002 batch model and is intentional.

## Alternatives Considered

- **Store the selection as a serialized id array on `AiHelperSetting`.** Rejected: loses referential integrity (no `on_delete` cascade when a project is deleted), can't be queried/joined, and complicates the "intersection with module-enabled projects" computation.
- **Per-project setting row (`AiHelperProjectSetting`) carrying a "register in vector DB" boolean.** Rejected: the selection is a global administrative decision about a global resource (the vector index); scattering it across project rows would require iterating all projects to compute the registration set and has no natural default for projects that have never opened their settings.
- **Discard the selection when the flag is turned ON.** Rejected by FR-006 — administrators toggling "register all" on and off must not lose their curated list.
- **Gate features on the global `vector_search_enabled?` only and rely on empty search results in out-of-scope projects.** Rejected: tools would still be advertised to the LLM and the UI would imply vector features exist where they return nothing; per-project gating is clearer and cheaper.

## Supersedes / Superseded By

Builds on [ADR-002](002-vector-scope-by-ai-helper-module.md); does not supersede it. The module-enabled gate remains the base scope, and this ADR narrows it with an optional selection.
