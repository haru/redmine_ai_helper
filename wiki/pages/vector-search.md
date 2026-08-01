---
title: Vector Search
type: reference
sources: [S002, S004, S008, S010, S012]
updated: 2026-08-01
---

# Vector Search

Semantic search over Redmine issues and wiki data, backed by **Qdrant** (S002).
It powers similar-issue search and the duplicate-issue check shown when creating
a new issue — both features are unavailable unless vector search is set up (S002).

## Embedding needs an embedding-capable provider

Embedding requires a provider that offers embedding models — **Anthropic does
not**, which is why the README warns that vector search "does not work with
Anthropic models" (S002). That warning was written when embedding always reused
the *normal* model profile.

Since the vector-model-profile feature, that is **no longer a hard block on your
chat model**: you can set a **dedicated vector model profile** so the normal
chat model stays Anthropic while embedding/summarization use, e.g., OpenAI
(S004). The embedding provider itself must still support embeddings — the system
does **not** validate that the chosen profile's model can embed; a bad
combination surfaces as an API error from the provider, and the settings screen
shows a note telling admins to verify the combination themselves (S004).

## Setup

Run Qdrant (e.g. `qdrant/qdrant` via Docker Compose, port 6333) (S002), then
manage the index with rake tasks (S002):

```bash
# create the index
bundle exec rake redmine:plugins:ai_helper:vector:generate RAILS_ENV=production
# register issue/wiki data (initial run can be slow)
bundle exec rake redmine:plugins:ai_helper:vector:regist RAILS_ENV=production
# delete the index (before recreating, e.g. after changing embedding model)
bundle exec rake redmine:plugins:ai_helper:vector:destroy RAILS_ENV=production
```

Run `vector:regist` **periodically via cron** so index data reflects issue
updates (S002). If the embedding model changes, `destroy` then re-create (S002).

## Vector model profile

An optional separate profile for the embedding **and** summarization work done
during index registration and search (S004). Configured on the global
`AiHelperSetting` via two added fields: `use_vector_model_profile` (boolean,
default `false`) and `vector_model_profile_id` (optional FK to an
`AiHelperModelProfile`) (S004). Existing rows migrate to
`use_vector_model_profile = false, vector_model_profile_id = nil`, so existing
users are unaffected (S004).

UI rules (S004):

- The "Select a vector-search model profile" checkbox sits under "Enable vector
  search" and is **hidden** while vector search is off.
- The profile dropdown shows only when the checkbox is on.
- Checkbox on + no profile selected → **validation error** on save.
- Unchecking and saving **clears `vector_model_profile_id` to nil** (the ID is
  not retained).

**Fallback behavior (contrast with the think model)**: when no vector profile is
set — checkbox off, *or* the referenced profile was later deleted leaving a
dangling reference — vector processing **silently falls back** to the normal LLM
profile and continues without error (S004). This is the opposite of the
[Think Model](./think-model.md), where a missing/invalid profile is surfaced as
an error rather than falling back.

## Result access control

Search runs through `VectorTools`, which applies **dual filtering**: results are
narrowed first by Qdrant metadata and then again after retrieval by Redmine
visibility/permission checks, so a semantic match can never leak an issue the
user may not see (S008). See [Tool System](./tool-system.md).

## Attachments in the index

When [multi-modal file support](./multi-modal-file-support.md) is enabled,
attachment contents are analyzed and folded into the vector index during
registration and similar-issue search, improving similarity matching for issues
carrying meaningful attachments (S002).

By default **every** module-enabled project is indexed; a "Register all
projects" toggle lets an admin pick specific projects instead, which also gates
where vector-dependent search works (S012). See
[Vector Search Internals](./vector-search-internals.md) for that selection model,
indexing, payload indexes, sync, and `ensure_indexes` (S010, S012).

## Related

- [Vector Search Internals](./vector-search-internals.md) — the subsystem's
  components, hybrid content, and rake tasks.
- [MCP Integration](./mcp-integration.md) — the Vector tool group
  (`find_similar_issues`, `ask_with_filter`) requires this setup.
- [Think Model](./think-model.md) — a related but *opposite* fallback policy.
- [Plugin Overview](./plugin-overview.md)
