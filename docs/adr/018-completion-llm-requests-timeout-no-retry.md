# ADR-018: Inline completion LLM requests use a short timeout and no retries

**Date**: 2026-08-20
**Status**: Accepted

## Context

Inline auto-completion (issue description, issue notes, wiki content) fires an LLM request
while the user is typing. Unlike chat or the health report, nobody is waiting on a completion
result: if it does not arrive quickly it is worthless, because the text it was computed for
has already changed.

Until this change, completion requests inherited RubyLLM's global HTTP configuration. Reading
`ruby_llm-1.16.0`, that means `request_timeout: 300` and `max_retries: 3`
(`lib/ruby_llm/configuration.rb`), and the retry middleware covers `POST` and retries on
`Faraday::TimeoutError` (`lib/ruby_llm/connection.rb`). A completion sent to an unresponsive
backend could therefore hold an application worker for up to 300 seconds × 4 attempts —
roughly 20 minutes — for a result that would be discarded on arrival.

GitHub issue #392 reports the user-visible consequence: with a slow LLM backend, saving an
issue hangs for minutes. The browser side of that pile-up (never aborting superseded `fetch`
calls) is fixed separately; this ADR covers the server side, where the same pile-up consumes
Puma/Passenger workers and degrades the whole Redmine instance for every user, not just the
one who was typing.

## Decision

1. **Completion LLM requests run with a bounded timeout, configurable and defaulting to 30
   seconds.** The value comes from `autocompletion.timeout` in
   `{REDMINE_ROOT}/config/ai_helper/config.yml`, validated to the range 1–600 seconds by
   `RedmineAiHelper::Util::ConfigFile.autocompletion_settings`. Out-of-range or non-numeric
   values fall back to 30 with a warning in the plugin log.

2. **Completion LLM requests never retry** (`max_retries: 0`). A retried completion competes
   with the newer request the user's next keystroke already triggered, so retrying multiplies
   worker occupancy without ever improving the answer the user sees.

3. **The bound applies to completion only.** The options travel as an optional
   `request_options:` keyword through `LlmProvider.get_llm_provider` into
   `LlmClient::BaseProvider`, which applies them to the per-request `RubyLLM::Context`.
   `RubyLLM.context` duplicates the global configuration before yielding it, so the override
   cannot leak. Chat, summaries, health reports and every other LLM call path pass no
   `request_options` and keep RubyLLM's global settings unchanged.

4. **A timeout is a normal outcome, logged at warn level, and surfaces as "no suggestion".**
   `IssueReadAgent#generate_text_completion` and `WikiAgent#generate_wiki_completion` rescue
   `Faraday::TimeoutError` ahead of their generic rescue, log a warning naming the context
   type and project, and return `""`. The controller answers `200` with
   `{"suggestion": ""}`; the editor simply shows no suggestion. RubyLLM has no timeout-specific
   error class, so `Faraday::TimeoutError` propagates unwrapped and is what we rescue.

## Consequences

**Positive**:

- A single completion can occupy a worker for at most the configured timeout instead of
  ~20 minutes, so one slow backend can no longer starve the instance of workers.
- Operators can tune the bound per installation without touching code, and a misconfigured
  value degrades to the default with an explicit log line rather than silently.
- The blast radius is confined to two methods: no other AI feature's latency behaviour changes,
  which keeps this fix reviewable against issue #392 rather than being a global tuning change.
- The five provider subclasses are untouched; the override is applied once in `BaseProvider`.

**Negative**:

- A backend that legitimately needs more than 30 seconds for a completion will now return no
  suggestion by default. This is the intended trade-off — such a completion arrives long after
  the text it was computed for has changed — but it does mean slow local models may need
  `autocompletion.timeout` raised.
- Completion no longer benefits from retrying a transient 5xx or connection blip. A failed
  completion is simply dropped; the user's next keystroke issues a fresh request, which is a
  better retry than the middleware's.
- Two subtly different timeout regimes now exist in the plugin (completion vs. everything
  else), which is a thing future contributors must know. This ADR is where that is recorded.

## Alternatives Considered

See `specs/045-fix-autocompletion-request-pileup/research.md` (R2, R3) for the full analysis.

- **Lower the global `RubyLLM.configure` timeout** (rejected): would change latency behaviour
  for chat, summaries and health reports, where a long-running request is legitimate and a user
  is actually waiting for it.
- **Add the branch to each provider's `build_context`** (rejected): the same change duplicated
  across five subclasses, against the DRY principle in the project constitution.
- **Wrap the call in `Timeout.timeout`** (rejected): a Ruby-level interrupt can leave the
  underlying `Net::HTTP` socket in an inconsistent state. Faraday's native `options.timeout`
  closes the connection cleanly.
- **Extend `BaseAgent`'s params with a provider override** (rejected): widens the agent base
  class's public API when the existing `attr_accessor :llm_provider` already suffices.
