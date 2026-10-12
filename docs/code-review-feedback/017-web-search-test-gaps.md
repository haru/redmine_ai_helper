# CRF-017: Web search tests skipped the negative routing path, read-only mode and the real payload

**Date**: 2026-10-12
**Source**: Local AI review (`/speckit-review-run`, tests agent)
**Feature**: branch `feature/071-web-search-citations`
**Files**: test/unit/llm_test.rb, test/unit/agents/web_search_agent_test.rb, test/functional/ai_helper_settings_controller_test.rb, test/functional/ai_helper_controller_test.rb, test/unit/agents/leader_agent_test.rb
**Category**: test-gap
**Related**: CRF-006, CRF-010

## Feedback

- The "disabled" and "unsupported profile" end-to-end tests stubbed `generate_steps` to `[]`, so a `web_search_agent` step was never routed while the feature was off; the unsupported test also had no `assert_not_empty @requests` and could pass vacuously.
- FR-008 (web search works in read-only mode) had no test.
- FR-003c (only the task leaves the system) was checked only against a fake chat, not the real captured request.
- Turning the setting off, `call_llm` persisting citations, and streaming with web search were untested.
- A controller test called `WebCitation.dedupe` directly and counted the result, duplicating a unit test without touching the controller.

## Original Code

```ruby
should "send no web search tool at all when web search is disabled" do
  use_profile("OpenAI", false)
  RedmineAiHelper::Agents::LeaderAgent.any_instance.stubs(:generate_steps).returns({ "steps" => [] })
```

## Fix

Added end-to-end tests that keep the `web_search_agent` step with the feature disabled or unsupported (the request is refused with "Agent is disabled" and no provider tool is sent), a read-only end-to-end test and an `enabled?` unit test, a payload test asserting the web search request holds only the system message and the task (no question, no goal), a streaming test, a settings "turn off" test, and a `call_llm` persistence test replacing the tautological one.

## Root Cause

The negative tests were written to assert "no tool on any request" and the simplest way to get requests was to skip the chat room, which removed the very routing the test was meant to guard. Requirements stated as guarantees (FR-003c, FR-008) were tested at the unit level with fakes, and CRF-010's "one top-level-to-payload test" was applied to the happy path only.

## Prevention

For each guarantee of the form "X never happens when Y", write the test with the input that would trigger X (here: a plan that routes to the disabled agent), not with an input that avoids it. Every privacy or "never sent" requirement gets an assertion on the real rendered/captured payload, and every collection asserted with `each` is first asserted non-empty.

**Promoted to**: Not yet
