---
title: Vector Search Internals
type: component
sources: [S002, S010, S012, S033]
updated: 2026-11-21
---

# Vector Search Internals

How the [Vector Search](./vector-search.md) subsystem turns Redmine data into
Qdrant vectors and keeps them in sync (S010).

> Provenance: DeepWiki auto-generated doc (S010); the rake-task names
> corroborate the README (S002).

## Components

| Class | Role |
|---|---|
| `VectorDb` | base class: index management + synchronization |
| `Qdrant` | HTTP client wrapper for the vector DB |
| `IssueVectorDb` / `WikiVectorDb` | entity-specific indexing |
| `AiHelperVectorData` | AR tracking model mapping Redmine object IDs → Qdrant UUIDs |
| `IssueContentAnalyzer` | LLM preprocessor building the "hybrid" content format |

## Hybrid content & embeddings

Issues are embedded from a **hybrid** format built by `build_hybrid_content`:
summary (structured metadata) + keywords + title + description (S010). Vector
dimensions are detected from the [LLM provider](./llm-provider-layer.md)'s
capabilities and used to initialize the Qdrant collection (S010). Getting the
hybrid formatting right is critical to similarity/duplicate relevance (S010).

## Collections & payload indexes

Collections carry payload fields for filtered search — `project_id`,
`status_id`, and others declared via `payload_index_declarations` (S010).
**Gotcha**: strict-mode environments (Qdrant Cloud) require payload indexes to be
created **explicitly**, separately from collection init; the `ensure_indexes`
rake task retrofits them onto existing collections (S010).

## Registration scope & project selection

Registration scope and project selection are on a separate page. See [Vector Search Registration Scope](./vector-search-registration-scope.md) (S010, S012, S033).

## Rake tasks

Beyond the three [setup tasks](./vector-search.md):

- `generate` — create the collection schema after detecting embedding dimensions (S010).
- `regist` — bulk-process issues/wikis, create schemas, register applicable
  data, and clean stale entries; `add_datas` iterates scoped records with retry
  logic and bulk upsert (S010).
- `ensure_indexes` — retrofit payload indexes onto existing collections (S010).
- `destroy` — wipe the index **and** the local `AiHelperVectorData` tracking
  records (S010).

## Search & staleness

Search flows `VectorDb#search` → `Qdrant#search_points`, returning payloads (for
filtered queries) and similarity scores (S010). The tracking model detects stale
entries by comparing Redmine record IDs against stored Qdrant UUID mappings and
handles deletions during sync, so **incremental** updates avoid a full reindex;
bulk operations are batched to respect API limits (S010).

## Related

- [Vector Search](./vector-search.md) — setup and the access-control filtering.
- [Tool System](./tool-system.md) · [LLM Provider Layer](./llm-provider-layer.md)
- [All-Projects Scope: Effects & Alternatives](./all-projects-scope-effects.md) —
  the setting that widens the base project scope here.
