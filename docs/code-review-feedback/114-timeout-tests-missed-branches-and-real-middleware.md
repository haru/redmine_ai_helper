# CRF-114: Timeout tests missed the non-ConnectionError branch and most real-middleware paths

**Date**: 2026-11-21
**Source**: Local AI review (speckit-review-run, 6 agents)
**Feature**: branch `feature/089-ruby-llm-2-2-upgrade`
**Files**: test/unit/agents/issue_read_agent_test.rb, test/unit/agents/wiki_agent_test.rb, test/functional/ai_helper_controller_test.rb, test/functional/ai_helper_controller_wiki_test.rb, test/functional/ai_helper_settings_controller_test.rb
**Category**: test-gap
**Related**: CRF-006, CRF-010, CRF-017

## Feedback

- `IssueReadAgent` tested the non-timeout branch only with a refused `ConnectionError`; a `ServerError` (which has no `timeout?`) was never driven, so `e.timeout?` without the `is_a?` guard would not fail any test.
- The only test through RubyLLM's real `ErrorMiddleware` covered the issue path and a read timeout. The wiki path, the embedding test, connect timeouts and an unwrapped Faraday error had none; the helper that builds errors was pinned only against hand-built shapes.
- No test checked the log text for the non-connection `RubyLLM::Error` of the settings test.

## Original Code

Tests built errors with `build_connection_error` and stubbed `chat`, so every layer below the stub was bypassed.

## Fix

Added: `ServerError` cases for both agents, a settings log test for `UnauthorizedError`, and controller tests that stub only `Faraday::Adapter::NetHttp#call` for issue, wiki and embedding (read and connect timeout, warn-not-error log, unwrapped `ParsingError` → 500).

## Root Cause

Tests were written per branch of the new code with the helper, not per member of the error union the branch receives. The cross-layer rule in AGENTS.md was applied to one path only.

## Prevention

For each new `rescue`/branch over an error union, add one test per distinct class the branch can receive (including one outside the guard's type), and for each user-facing entry point at least one test that stubs only the transport so the library middleware runs.

**Promoted to**: Not yet
