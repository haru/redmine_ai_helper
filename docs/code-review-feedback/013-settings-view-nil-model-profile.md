# CRF-013: Settings page crashed when web search was on and no main model profile was set

**Date**: 2026-10-12
**Source**: Local AI review (`/speckit-review-run`, code agent)
**Feature**: branch `feature/071-web-search-citations`
**Files**: app/views/ai_helper_settings/_general_tab.html.erb, specs/071-web-search-citations/contracts/settings-ui.md, test/functional/ai_helper_settings_controller_test.rb
**Category**: edge-case
**Related**: CRF-001

## Feedback

The general tab called `@setting.model_profile.llm_type` to decide the "unsupported profile" warning. `model_profile` can be nil: `belongs_to :model_profile` is not required in Redmine (no `load_defaults`), `AiHelperSetting.find_or_create` creates the row without a profile, and the Model tab's select allows a blank value. With web search enabled and no profile, every tab is rendered by `render_tabs`, so the whole settings page returned 500 and the admin could not reach the Model tab to fix it.

## Original Code

```erb
<% if @setting.web_search_enabled && !RedmineAiHelper::LlmProvider.web_search_supported?(@setting.model_profile.llm_type) %>
```

## Fix

Guard on the profile (no warning when it is unset), and add a functional test that renders the index with `web_search_enabled: true` and `model_profile_id: nil`. The contract `settings-ui.md` §1, which prescribed the unguarded line, and research.md R10 were corrected (SF-005).

## Root Cause

The view line was copied verbatim from the contract, and the contract assumed a main profile always exists because the chat cannot work without one. Nobody checked whether the association is optional at the model level or whether a settings row can exist without it. The functional tests always created a profile in `setup`, so the nil path was never rendered.

## Prevention

Before dereferencing a `belongs_to` association in a view or a settings path, check whether the association can be nil (no `optional: false`/presence validation, rows created by `find_or_create`, blank-able selects). If it can, guard it and add a test that renders the page with the association unset.

**Promoted to**: Not yet
