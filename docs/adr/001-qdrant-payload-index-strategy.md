# ADR-001: Auto-create Qdrant payload indexes for filtered fields

**Date**: 2026-05-23
**Status**: Proposed

## Context

The plugin relies on Qdrant filter queries (e.g. `must: [{ key: "project_id", match: { value: X } }]`) to restrict similarity search to the current Redmine project and other axes such as `tracker_id`, `status_id`, `priority_id`, `author_id`, `assigned_to_id`, `version_id`, `created_on`, `updated_on`, `due_date`. These fields are exposed to the LLM as filter keys via the `ask_with_filter` tool.

Qdrant Cloud (and self-hosted clusters with strict mode enabled, available since recent Qdrant releases) reject filter queries on payload fields without an explicit payload index. Self-hosted Qdrant with strict mode disabled silently falls back to a full payload scan. This asymmetry is the root cause of issue #292, where the same plugin code works on local Qdrant but fails on Qdrant Cloud with `Index required but not found for "project_id"`.

A user can manually create the index via the Qdrant REST API, but this is undocumented and breaks the "drop-in plugin" expectation.

## Decision

1. The plugin will declare the set of payload index requirements per collection (Issue: 10 fields, Wiki: 3 fields) as part of each `VectorDb` subclass.
2. `VectorDb#generate_schema` will create the collection and then call `ensure_payload_indexes`, which creates each declared index if absent and is idempotent if already present with a matching schema type.
3. A new Rake task `redmine:plugins:ai_helper:vector:ensure_indexes` will retrofit existing collections without re-embedding data.
4. If an existing index uses an incompatible schema type, the plugin will not auto-delete or auto-recreate it. Instead, it logs the mismatch and the Rake task exits non-zero so the operator must intervene.
5. No automatic startup migration. Index reconciliation happens only via explicit Rake tasks.

## Consequences

**Positive**:
- The plugin works out-of-the-box on Qdrant Cloud / strict mode clusters.
- Existing users can adopt the fix without re-embedding (which has cost and time implications for large instances).
- Operator intervention is required only for the unusual case of pre-existing incompatible indexes, surfaced as a clear non-zero exit.

**Negative**:
- The plugin now issues additional `PUT /collections/{name}/index` requests during schema generation (10 + 3 calls one-time per environment), introducing a brief additional failure surface.
- A retrofit Rake task adds maintenance surface (documentation, tests).
- The non-zero exit on mismatch may surprise CI/cron-driven operators initially; mitigated via quickstart documentation.

## Alternatives Considered

- **Try-create-and-ignore-errors**: blindly call `create_index` on every schema generation and discard 4xx. Rejected because mistaking a type-mismatch error for a transient failure would silently leave the cluster broken, and tests for idempotency would be fragile.
- **Auto-delete-and-recreate on mismatch**: convenient but irreversible. Could destroy operator-customised indexes (e.g. those with custom on-disk options). Rejected for safety.
- **Automatic startup migration**: simpler UX but risks running long index-building operations against large collections during a Redmine restart. Rejected in favour of explicit Rake tasks operators can schedule.
- **Document manual `curl` steps only**: requires every Qdrant Cloud user to hit the REST API themselves, defeating the plugin's drop-in goal. Rejected.
