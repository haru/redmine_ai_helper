# ADR-074: Classify LLM network failures with RubyLLM::ConnectionError

**Date**: 2026-11-21
**Status**: Accepted

## Context

RubyLLM 2.2 converts the network failures of a provider request (`Faraday::ConnectionFailed`, `Faraday::TimeoutError`, `Faraday::SSLError`) into `RubyLLM::ConnectionError` in its error middleware. The original Faraday error stays available as `cause`. Before 2.2 these errors reached the plugin unwrapped.

The plugin told timeouts apart from other failures by Faraday type: the inline completion agents rescued `Faraday::TimeoutError`, and the embedding connection test checked `Faraday::TimeoutError` and `Faraday::ConnectionFailed` caused by `Net::OpenTimeout`. With 2.2 those checks never match. A slow backend then produced an error-level log with a backtrace on every completion, and the embedding test showed the raw provider message instead of the timeout message. ADR-018, ADR-062 and ADR-071 describe the Faraday-based behavior.

## Decision

1. A timeout is `error.is_a?(RubyLLM::ConnectionError) && error.timeout?`. `ConnectionError#timeout?` is true for a read timeout and for a connect timeout (`Faraday::ConnectionFailed` wrapping `Net::OpenTimeout`). The condition is written inline at the three call sites (issue completion, wiki completion, embedding connection test) because the library already owns the classification.
2. `Faraday::Error` is removed from the `rescue` clauses around LLM calls (`Llm#generate_text_completion`, `IssueReadAgent#generate_text_completion`, `IssueContentAnalyzer#analyze`, and the embedding test's expected-error check). RubyLLM 2.2 does not let Faraday errors through on these paths, so a raw Faraday error is an unexpected defect and surfaces. The Qdrant client keeps its Faraday handling because it does not go through RubyLLM.
3. `WikiAgent#generate_wiki_completion` keeps its catch-all `rescue => e`. The timeout clause is changed to `rescue RubyLLM::ConnectionError`, and inside it the timeout case logs a warning while any other connection error logs the same error and backtrace as the catch-all. Narrowing the catch-all would change what non-LLM failures do and is out of scope.
4. MCP tool call failures stay on RubyLLM 2.2's default: a transport failure, 429, 5xx or stdio server exit becomes a tool result for the model and the chat continues. A 4xx refusal other than 429 and a failure to list tools still raise. The plugin adds no `rescue` around tool calls. A test with a stdio server that exits during `tools/call`, run through the real conversation loop with `RubyLLM::TestHelper`, guards the first behavior. No test is written for the 4xx refusal, because it needs an HTTP server and exercises RubyLLM only.
5. Tests that simulate an LLM network failure build the same shape as `ErrorMiddleware` (a `ConnectionError` whose `cause` is the Faraday error) through `RedmineAiHelper::TestSupport::ConnectionErrors`. One controller test stubs only `Faraday::Adapter::NetHttp#call` so the real middleware runs.

This ADR replaces the "`Faraday::TimeoutError` propagates unwrapped and is what we rescue" statement of ADR-018 and the `Faraday::Error` rescue lists of ADR-062 and ADR-071.

## Consequences

- A connect timeout on a completion request is now a warning, like a read timeout. Before, it was an error with a backtrace.
- The embedding connection test shows the timeout message for both kinds of timeout, as before.
- A `ConnectionError` built without a cause reports `timeout?` as false, so tests must use the helper.
- If a later RubyLLM release lets a Faraday error through again, these paths raise instead of returning an empty result.

## Alternatives Considered

- Extract a shared `timeout?` helper: it would only wrap one library call.
- Check `e.cause.is_a?(Faraday::TimeoutError)`: misses the connect timeout and diverges from the library's own check.
- Keep `Faraday::Error` in the rescue lists: lists an error type that cannot occur on these paths and hides what the clause expects.
- Narrow the wiki catch-all to `RubyLLM::Error`: changes the behavior for non-LLM failures and needs separate approval.
- Rescue MCP tool call errors in the plugin: duplicates RubyLLM 2.2's handling and would hide the 4xx refusals it deliberately raises.
- WebMock or VCR for the network tests: new dependency; a single adapter stub is enough.
