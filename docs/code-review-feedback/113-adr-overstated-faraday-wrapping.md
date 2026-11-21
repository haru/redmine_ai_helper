# CRF-113: ADR-074 and the wiki said RubyLLM 2.2 never lets Faraday errors through

**Date**: 2026-11-21
**Source**: Local AI review (speckit-review-run, 6 agents)
**Feature**: branch `feature/089-ruby-llm-2-2-upgrade`
**Files**: docs/adr/074-ruby-llm-2-2-connection-error-classification.md, wiki/pages/completion-request-timeout-policy.md, wiki/pages/embedding-connection-test.md, docs/adr/README.md
**Category**: doc-comment
**Related**: CRF-005, CRF-007, CRF-011, CRF-109

## Feedback

The comments review compared the claim with `ruby_llm-2.2.3/lib/ruby_llm/transport/error_middleware.rb`: `NETWORK_FAILURES` wraps only `Faraday::ConnectionFailed`, `Faraday::TimeoutError` and `Faraday::SSLError`. Other Faraday errors (for example `ParsingError`) pass through. ADR-018, 062 and 071 were also replaced in part without any marker in the ADR index.

## Original Code

"RubyLLM 2.2 does not let Faraday errors through on these paths" / "A raw `Faraday::Error` no longer reaches these paths".

## Fix

Docs name the three wrapped classes and say any other Faraday error surfaces as HTTP 500; controller tests pin the unwrapped case. The README marks ADR-018/062/071 "partially superseded by ADR-074".

## Root Cause

The summary of the library behaviour came from the 2.2 changelog wording, not from the middleware source. AGENTS.md already requires reading the library source before documenting what a shared path does for every provider/protocol.

## Prevention

A doc sentence of the form "X can no longer happen" cites the exact list or line in the library source it rests on, and names what is not covered. An ADR that replaces statements of older ADRs also marks them in the ADR index.

**Promoted to**: Not yet
