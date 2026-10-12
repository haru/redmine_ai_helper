# SF-005: Settings contract dereferenced the main model profile without checking it can be unset

**Date**: 2026-10-12
**Feature**: specs/071-web-search-citations (branch `feature/071-web-search-citations`)
**Artifact**: contracts/settings-ui.md, research.md (R10)
**Category**: convention-unknown
**Related**: None

## Feedback

A local review (`/speckit-review-run`) found that the settings page returns 500 when web search is enabled and no main model profile is set; the user approved fixing all findings ("全て修正して"), including this contract correction (code side: CRF-013).

## What the AI Wrote

contracts/settings-ui.md §1 prescribed the view line verbatim:

```erb
<% if @setting.web_search_enabled && !RedmineAiHelper::LlmProvider.web_search_supported?(@setting.model_profile.llm_type) %>
```

research.md R10 said: "if `web_search_enabled` is true and `LlmProvider.web_search_supported?(@setting.model_profile.llm_type)` is false, show the warning."

## Correction

The contract line now guards on `@setting.model_profile`, and a bullet was added: when the main model profile is unset, no warning is shown and the page must not error, because `model_profile` is not required (`find_or_create` creates the row without it and the Model tab allows a blank value). R10 got the same sentence.

## Root Cause

The AI assumed a main profile always exists because the chat cannot work without one, and wrote the contract at the level of an exact code line. It did not read `AiHelperSetting` (`belongs_to :model_profile` without a presence validation), `find_or_create`, or the Model tab's `include_blank: true`, which together show the association can be nil. The contract was then implemented verbatim, so the defect passed straight into the code.

## Prevention

When a spec or contract dereferences an association or setting (`a.b.c`), check in the model whether it can be nil (no presence validation, rows created by `find_or_create`, blank-able form fields) and state the behaviour for the unset case explicitly in the contract.

**Promoted to**: Not yet
