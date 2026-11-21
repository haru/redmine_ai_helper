---
title: Vector Search
type: reference
sources: [S002, S004, S008, S010, S012, S033, S039]
updated: 2026-11-21
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
shows a note telling admins to verify the combination themselves (S004). A
"Test connection" button on the vector tab now does that check before saving — see
[Embedding Connection Test](./embedding-connection-test.md) (S039).

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

## Vector model profile & attachments

The vector model profile and attachment indexing are on a separate page. See [Vector Model Profile & Attachments in the Index](./vector-search-model-profile-and-attachments.md) (S002, S004, S010, S012, S033).

## Result access control

Search runs through `VectorTools`, which applies **dual filtering**: results are
narrowed first by Qdrant metadata and then again after retrieval by Redmine
visibility/permission checks, so a semantic match can never leak an issue the
user may not see (S008). See [Tool System](./tool-system.md).

## Related

- [Vector Search Internals](./vector-search-internals.md) — the subsystem's
  components, hybrid content, and rake tasks.
- [MCP Server Endpoint](./mcp-server-endpoint.md) — the Vector tool group
  (`find_similar_issues`, `ask_with_filter`) requires this setup.
- [Think Model](./think-model.md) — a related but *opposite* fallback policy.
- [Plugin Overview](./plugin-overview.md)
