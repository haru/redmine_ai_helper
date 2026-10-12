# CRF-012: Hand-written branching where a single path or data mapping suffices

**Date**: 2026-10-11
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `feature/070-prompt-caching`
**Files**: lib/redmine_ai_helper/llm_client/anthropic_provider.rb, base_agent.rb, langfuse_util/langfuse_wrapper.rb, util/system_prompt.rb, assets/javascripts/settings/ai_helper_model_profile.js
**Category**: readability
**Related**: None

## Feedback

The simplify reviewer suggested: collapse the three-branch `case` (with an empty `when nil`) in `AnthropicProvider#apply_instructions`; replace two `unless ...nil?` assignments with `merge({...}.compact)`; turn the cache metadata key mapping into a constant used with `slice`/`transform_keys`; extract `current_user_info_json` from a `begin ... end` memoization block; and make `handleLlmTypeChange` use one style for element lookups.

## Original Code

```ruby
usage[:cache_read_tokens] = tokens.cache_read unless tokens.cache_read.nil?
usage[:cache_write_tokens] = tokens.cache_write unless tokens.cache_write.nil?
```

## Fix

Applied all five suggestions. `fixed_prompt` is now memoized like `context_prompt`, and `langfuse_usage_from` logs a warning when the provider reports no input tokens.

## Root Cause

Each branch was added incrementally per task, so the AI kept the shape of the first draft instead of revisiting it once the full set of cases was known; key mappings were written as code because they started with one key.

## Prevention

After finishing a method that handles a type union or several optional keys, rewrite it as normalize-then-single-path or as a data mapping (constant + `slice`/`transform_keys`/`compact`) before committing.

**Promoted to**: Not yet
