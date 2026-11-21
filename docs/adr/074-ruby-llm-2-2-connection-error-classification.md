# ADR-074: Classify LLM network failures with RubyLLM::ConnectionError

**Date**: 2026-11-21
**Status**: Accepted

## Context

RubyLLM 2.2 converts the network failures of a provider request (`Faraday::ConnectionFailed`, `Faraday::TimeoutError`, `Faraday::SSLError`) into `RubyLLM::ConnectionError` in its error middleware. The original Faraday error stays available as `cause`. Before 2.2 these errors reached the plugin unwrapped.

The plugin told timeouts apart from other failures by Faraday type: the inline completion agents rescued `Faraday::TimeoutError`, and the embedding connection test checked `Faraday::TimeoutError` and `Faraday::ConnectionFailed` caused by `Net::OpenTimeout`. With 2.2 those checks never match. A slow backend then produced an error-level log with a backtrace on every completion, and the embedding test showed the raw provider message instead of the timeout message. ADR-018, ADR-062 and ADR-071 describe the Faraday-based behavior.

## Decision

1. A timeout is `RedmineAiHelper::Util::ConnectionErrorHelper.timeout?(error)`, which is `error.is_a?(RubyLLM::ConnectionError) && error.timeout?`. `ConnectionError#timeout?` is true for a read timeout and for a connect timeout (`Faraday::ConnectionFailed` wrapping `Net::OpenTimeout`). The helper is the one place the three call sites (issue completion, wiki completion, embedding connection test) share; the library still owns the classification. `ConnectionErrorHelper.describe` adds the class of the `cause` (and of the exception a Faraday error wraps) to error-level log lines, so a refused connection can be told from a DNS failure.
2. `Faraday::Error` is removed from the `rescue` clauses around LLM calls (`Llm#generate_text_completion`, `IssueReadAgent#generate_text_completion`, `IssueContentAnalyzer#analyze`, and the embedding test's expected-error check). RubyLLM 2.2's `ErrorMiddleware` wraps only `Faraday::ConnectionFailed`, `Faraday::TimeoutError` and `Faraday::SSLError` (`NETWORK_FAILURES` in `transport/error_middleware.rb`). Any other Faraday error, for example `Faraday::ParsingError`, is not wrapped. Such an error is treated as a defect and surfaces (HTTP 500 for the completion endpoints). Controller tests stub `Faraday::Adapter::NetHttp#call` to pin both the wrapped and the unwrapped case. The Qdrant client keeps its Faraday handling because it does not go through RubyLLM.
3. `WikiAgent#generate_wiki_completion` and `Llm#generate_wiki_completion` rescue only `RubyLLM::Error`, like their issue counterparts. In `WikiAgent` the timeout case logs a warning and any other `RubyLLM::Error` logs an error with a backtrace; both return an empty string. The earlier catch-all `rescue => e` returned an empty completion for a defect such as `NoMethodError`, which AGENTS.md forbids, so those now surface as HTTP 500. `Llm#text_completion` and the agents still return an empty string for every `RubyLLM::Error`, including a non-transient one such as `UnauthorizedError`; the log line is the only signal for a bad credential there. Narrowing that is a separate decision.
4. MCP tool call failures stay on RubyLLM 2.2's default: a transport failure, 429, 5xx or stdio server exit becomes a tool result for the model and the chat continues. A 4xx refusal other than 429 and a failure to list tools still raise. The plugin adds no `rescue` around tool calls. A test with a stdio server that exits during `tools/call`, run through the real conversation loop with `RubyLLM::TestHelper`, guards the first behavior. No test is written for the 4xx refusal, because it needs an HTTP server and exercises RubyLLM only.
5. Tests that simulate an LLM network failure build the same shape as `ErrorMiddleware` (a `ConnectionError` whose `cause` is the Faraday error) through `RedmineAiHelper::TestSupport::ConnectionErrors`. The helper lives in `test/support/connection_errors.rb` and raises `ArgumentError` for a kind outside `ConnectionErrors::KINDS`. Controller tests for the issue completion, the wiki completion and the embedding connection test stub only `Faraday::Adapter::NetHttp#call`, so the real middleware runs for a read timeout and for a connect timeout.

This ADR replaces the "`Faraday::TimeoutError` propagates unwrapped and is what we rescue" statement of ADR-018 and the `Faraday::Error` rescue lists of ADR-062 and ADR-071. The README table marks those three as partially superseded.

## Consequences

- A connect timeout on a completion request is now a warning, like a read timeout. Before, it was an error with a backtrace.
- The embedding connection test shows the timeout message for both kinds of timeout, as before.
- A `ConnectionError` built without a cause reports `timeout?` as false, so tests must use the helper.
- If a later RubyLLM release lets one of the three wrapped Faraday errors through again, these paths raise instead of returning an empty result.
- A defect inside the wiki completion path now returns HTTP 500 instead of an empty suggestion.

## Alternatives Considered

- Write the `is_a?(ConnectionError) && timeout?` condition inline at each call site: three copies of the same predicate and of the log wording drifted apart in review.
- Check `e.cause.is_a?(Faraday::TimeoutError)`: misses the connect timeout and diverges from the library's own check.
- Keep `Faraday::Error` in the rescue lists: lists an error type that cannot occur on these paths and hides what the clause expects.
- Keep the wiki catch-all `rescue => e`: it hides defects behind an empty completion and conflicts with the no-fallback rule.
- Rescue MCP tool call errors in the plugin: duplicates RubyLLM 2.2's handling and would hide the 4xx refusals it deliberately raises.
- WebMock or VCR for the network tests: new dependency; a single adapter stub is enough.
