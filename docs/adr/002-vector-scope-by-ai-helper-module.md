# ADR-002: Scope vector data registration to projects with ai_helper module enabled

**Date**: 2026-05-24
**Status**: Proposed

## Context

The `rake redmine:plugins:ai_helper:vector:regist` task currently embeds every Issue and WikiPage in the Redmine instance, regardless of whether the project that owns them has the `ai_helper` project module enabled. This produces three operational problems:

1. **Wasted embedding cost** — embeddings are generated and stored for projects whose users will never invoke AI Helper, increasing OpenAI / Anthropic / Gemini API spend proportionally to the unused project share.
2. **Search noise** — vector similarity search returns matches from projects whose users have explicitly opted out, which then need to be filtered out at the read path or risk leaking context (the read path already filters by view permissions, but registering this data still consumes vector storage and weight).
3. **No removal path for opt-out** — once a project disables the `ai_helper` module, the previously embedded data lingers in Qdrant indefinitely; there is no operator-facing way to clean it up short of full reindexing.

The plugin already treats `ai_helper` as a project module gate at the read path (`Project#module_enabled?(:ai_helper)` is checked in `PermissionChecker`, view hooks, and tool dispatch). Aligning the write path to the same gate keeps the model consistent.

## Decision

1. `vector:regist` will register vector data only for Issues and WikiPages whose project has the `ai_helper` module enabled. The set is computed once at task start as `Project.joins(:enabled_modules).where(enabled_modules: { name: "ai_helper" })`.
2. The same task will, after registration, remove vector data whose source object is no longer in scope. "In scope" means: the source row still exists in Redmine **and** its project has the `ai_helper` module enabled. Either condition failing makes the record a deletion candidate.
3. Project archive state (`Project.status == STATUS_ARCHIVED`) is **not** part of the gate. As long as the module is enabled on an archived project, its Issues and Wikis remain registered. Read-side permission checks already handle visibility to users.
4. Cleanup is best-effort. Per-vector Qdrant failures are logged at warn level via `ai_helper_logger`, registered to per-collection failure counters, and processing continues. The Rake task exits 0 regardless of failure count; failed deletions are re-attempted on the next run, achieving eventual consistency.
5. Synchronisation is batch-only. Toggling the `ai_helper` module on a project does not touch the vector store until the next `vector:regist` run.
6. No new database tables, columns, or migrations. The mechanism reuses Redmine's `enabled_modules` table as the single source of truth and the existing `ai_helper_vector_data` table for bookkeeping.

## Consequences

**Positive**:

- Operators only pay the embedding cost for projects that actually use AI Helper.
- Search results no longer surface vectors from opted-out projects.
- A symmetric opt-in / opt-out lifecycle exists: disabling the module removes data on the next batch, re-enabling brings it back.
- No schema change, no new operational primitives, no fallback paths.

**Negative**:

- Module toggles take effect only on the next `vector:regist` run; operators must understand the batch model.
- A long-running `vector:regist` with intermittent Qdrant failures will leave some entries un-deleted until the next run. We accept this as eventual consistency rather than introducing retry/backoff machinery (KISS, YAGNI).
- The `clean_vector_data` method now returns aggregated counts and is no longer called implicitly from `add_datas`. Callers outside the Rake task that previously relied on the implicit cleanup behaviour must be updated.

## Alternatives Considered

- **Synchronous cleanup on `EnabledModule` deletion**: hook into Redmine's model lifecycle to delete vector data the moment the module is disabled. Rejected because it puts an external service call (Qdrant) on the project-settings save path, which would surface as a UI failure mode and tie request latency to Qdrant availability. The batch model isolates failures to a sysadmin-controlled context.
- **Soft-filter at query time only**: keep all data in Qdrant but filter `must_not` clauses by `ai_helper_disabled_project_ids` on every search. Rejected because it does not address the embedding cost driver (problem 1) and grows complexity at the read path for every tool that issues vector queries.
- **Track scope in a new `ai_helper_vector_scopes` table**: maintain plugin-side mirror state of which projects are in scope. Rejected because it duplicates `enabled_modules`, introduces a synchronisation problem, and requires a migration that this ADR explicitly avoids.
- **Use `Project.active` to additionally exclude archived projects**: rejected by Clarifications Q1 in spec.md — archived projects with the module enabled remain in scope.
- **Fail the Rake task on any Qdrant delete error**: rejected because a single transient failure (network blip, Qdrant restart) would block every other deletion in the same run and require manual intervention. The eventual-consistency model is intentional and aligns with Constitution III "no fallback" by surfacing the failure (warn log + non-zero failure counter) without silently retrying inside the same run.

## Supersedes / Superseded By

This ADR introduces a new behavior and does not supersede any prior ADR.
