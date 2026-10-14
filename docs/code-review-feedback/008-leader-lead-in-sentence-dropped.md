# CRF-008: Leader prompt lead-in sentence dropped when splitting the template

**Date**: 2026-10-11
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `feature/070-prompt-caching`
**Files**: assets/prompt_templates/leader_agent/system_prompt_context.yml, system_prompt_context_ja.yml, test/unit/util/system_prompt_test.rb
**Category**: convention-violation
**Related**: None

## Feedback

The code and comment reviewers found that the sentence "The following is reference information for you." (ja: 「以下はあなたの参考知識です。」) had been deleted from `leader_agent/system_prompt(_ja).yml` but not carried into the new `system_prompt_context(_ja).yml`. Task T019 and research.md say to move everything from that sentence onward "without changing wording", FR-009 forbids prompt wording changes other than reordering, and ADR-051 states "Prompt wording is unchanged; only positions move."

## Original Code

```yaml
template: |-
  ----

  Reference information:
```

## Fix

Restored the sentence and the blank line after it as the first lines of both context templates, and added `test_context_prompt_starts_with_reference_lead_in` asserting the English and Japanese context prompts start with it.

## Root Cause

The AI split the template at the `----` separator, the visually obvious boundary, instead of at the boundary the task named ("from that sentence onward"). The sentence was removed from the fixed template as instructed, but the move into the new template only copied text from the separator. No test compared the old and new prompt text, so the loss was invisible.

## Prevention

When a task says to move prompt text "without changing wording", verify that the concatenation of the new templates equals the original text (modulo ordering) — e.g. diff `develop:<old template>` against the new pieces — and add a test that pins the first line of each moved block in every locale.

**Promoted to**: Not yet
