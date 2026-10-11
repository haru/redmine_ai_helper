# CRF-010: Prompt caching tests missed cache stability, explicit profiles and the end-to-end payload

**Date**: 2026-10-11
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `feature/070-prompt-caching`
**Files**: test/unit/util/system_prompt_test.rb, test/unit/agents/leader_agent_test.rb, test/unit/base_agent_test.rb, test/unit/llm_client/anthropic_provider_test.rb, base_provider_test.rb, gemini/open_ai/open_ai_compatible/azure_open_ai_provider_test.rb, test/test_helper.rb, test/javascript/settings/ai_helper_model_profile.test.js
**Category**: test-gap
**Related**: CRF-006

## Feedback

The test reviewer found:
- No test proved the fixed part stays identical across users, projects, pages and time — the property that makes caching work; tests only checked that a few known patterns were absent.
- No Anthropic test used an explicit `model_profile:` (think-model path), so the profile flag could come from the wrong profile unnoticed.
- No test checked that an agent's real `system_prompt` reaches Anthropic as two system blocks; provider tests used hand-built `Instructions` and agent tests mocked `create_chat`.
- The JS test never checked that the caching field is hidden on load for non-Anthropic types.
- The base provider test mocked `RubyLLM::Chat`/`RubyLLM::Context` (not external servers) and asserted `expects(:cache_until_here).never` on a method that does not exist.
- The same "one uncached system message" block was duplicated in four provider tests.

## Original Code

```ruby
should "never enable caching" do
  @mock_chat.stubs(:with_instructions)
  @mock_chat.expects(:with_caching).never
  @mock_chat.expects(:cache_until_here).never
  @provider.create_chat(instructions: @instructions)
end
```

## Fix

Added equality tests for `fixed` (and inequality for `variable`) across two contexts in `SystemPrompt`, `LeaderAgent` and `BaseAgent`; explicit-profile tests in both directions; end-to-end tests rendering the Anthropic payload from `LeaderAgent#assistant.chat` and `ProjectAgent#assistant.chat`; an `it.each` hidden-on-load JS test; rewrote the base provider tests on a real chat (`chat.caching`, system messages); moved the shared assertion into `ProviderTestAssertions#assert_single_uncached_system_message` in `test/test_helper.rb`.

## Root Cause

Tests were written per unit, mirroring the tasks list, so properties that only exist across units (agent → provider → payload) or across calls (cache stability) had no owner. Negative assertions ("does not contain X") were used where the real requirement is an invariant ("is equal across calls"). Mocks were chosen for convenience where a real RubyLLM chat was cheap to build.

## Prevention

For a cache-related feature, assert the cache key's invariant directly: build two instances with every per-request input changed and `assert_equal` the cached part. When a value crosses layers (agent → provider → wire), add at least one test from the top-level entry point to the rendered payload. Do not mock library classes that can be instantiated locally; never write `expects(...).never` on a method name without checking the class defines it.

**Promoted to**: AGENTS.md
