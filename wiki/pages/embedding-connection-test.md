---
title: Embedding Connection Test
type: component
sources: [S039, S040]
updated: 2026-10-08
---

# Embedding Connection Test

A "Test connection" button under the embedding model field on the vector tab
checks, **before saving**, that the embedding model works. It posts the four
unsaved form values — base model profile, "use vector model profile" and its
profile, and the embedding model name — to
`POST /ai_helper_settings/test_embedding_connection` (S039). It saves nothing
and never touches the vector DB (S039). This complements the Qdrant connection
test; the [vector search](./vector-search.md) note that a bad profile/model
combination only surfaces as a provider error is exactly what this button
catches early.

## Same profile as real registration

The profile is chosen by `AiHelperSetting#vector_llm_model_profile`: the
dedicated vector profile when `use_vector_model_profile` is on and an ID is set
(`RecordNotFound` if it was deleted), otherwise the base `model_profile` (S039).
`LlmProvider.get_vector_llm_provider` now calls the same method, so the test and
real registration cannot drift apart (S039). The controller builds an unsaved
`AiHelperSetting.new` from the form values and calls it; missing or deleted
profiles return 422 before anything is sent to the provider (S039).

## What it sends and checks

`LlmProvider.test_embedding(profile:, embedding_model:)` embeds the fixed text
`"connection test"` once — no Redmine data is sent (S039). The result must be a
non-empty array of numbers, whose length is shown as the dimension
(`detect_vector_size` uses the same `vectors.length`, so it matches registration);
anything else raises `UnexpectedEmbeddingResponseError` (S039). Error text shown
to the admin is truncated to 500 characters; the log keeps the full message (S039).

To use an unsaved model name, `BaseProvider#embed` gained an
`embedding_model:` keyword whose default is the saved setting, so existing
callers are unchanged (S039). See [LLM Provider Layer](./llm-provider-layer.md).

## Timeout: 10 seconds per request, no retries

The provider is built with `request_options: { request_timeout: 10, max_retries: 0 }`
(RubyLLM defaults are 300 s and 3 retries) (S039). Gotchas (S039):

- The limit applies **per HTTP request**, not to the whole test. For OpenAI,
  Gemini and Anthropic the first `context` call may fetch the provider's model
  list (`ensure_model_registered!`) when the profile's *chat* model is not in
  RubyLLM's registry, so a slow list plus a slow embed can take about 20 s, and a
  wrong chat model name also fails this test.
- `fetch_and_register_model!` now applies `request_options` to its own
  configuration; it previously always used the 300 s default.
- Timeout detection: faraday-net_http raises `Faraday::TimeoutError` for read
  timeouts but wraps the connect timeout (`Net::OpenTimeout`) in
  `Faraday::ConnectionFailed`, so the controller checks both (the latter via
  `cause`).
- Wrapping the call in `Timeout.timeout` was rejected as unsafe (S039).

## The "dimension" and "embedding URL" settings were removed

`dimension` and `embedding_url` used to be saved by the settings form but were
never read in `app/` or `lib/`; the real dimension is detected from one
embedding, and Azure OpenAI embeddings use the profile's `base_uri` (S039).
Both columns, their form fields, `embedding_url_enabled?`, and the JS
`modelTypeChanged` were then removed; stale form posts that still send them are
silently ignored because they are no longer safe attributes (S040).

## Front end

The Qdrant and embedding tests share `bindConnectionTest` in
`ai_helper_settings.js` (progress text, disabled button, request counter that
drops stale responses, clear on input change); success reads
"Connection successful (Dimension: n)" (S039). The model-profile screen's separate
test script was deliberately left out of the sharing (S039).

## Related

- [Vector Search](./vector-search.md) · [Vector Search Internals](./vector-search-internals.md)
- [LLM Provider Layer](./llm-provider-layer.md)
