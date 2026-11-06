# CRF-084: Popup CSS tests covered only stacking, the test parser misread some constructs, and fixtures and listeners leaked

**Date**: 2026-11-01
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, types, simplify agents)
**Feature**: branch `feature/083-chat-form-popup` (specs/083-chat-form-popup)
**Files**: test/javascript/chat/ai_helper_chat_popup_css.test.js, test/javascript/chat/ai_helper_chat_popup.test.js, test/javascript/chat/ai_helper_chat.test.js, test/functional/ai_helper_view_hook_test.rb
**Category**: test-gap
**Related**: CRF-077

## Feedback

- Deleting the close-button rule, `position: fixed`, the handle rules, the narrow-screen media rule, `display: flex !important`, the transition or the pending rule left every test passing.
- Negative CSS assertions missed `inset-block`, `100svw`, `:root.aihelper-popup-pending` and similar spellings; `parseRules` silently misread `:is(a, b)`, nested `@media`, `url()` with `;`, upper-case property names and declarations without a colon.
- A 'moves the sidebar first' test passed with the sidebar already first; `init()` window listeners piled up between tests; Number.isFinite, the fold-state history jump and the open-with-failure path had no test.
- The animation test recorded only `left`.

## Original Code

```js
expect(sidebarWrapper.firstChild).toBe(sidebar);   // already true before initSidebar
```

## Fix

A contract block asserts each rule of ui-contract.md and the NARROW_QUERY/CSS sync, the parser throws on the unmodelled constructs (with a table row each), negative checks cover the equivalent spellings and assert the searched region exists, the move test starts with a sibling first, listeners are removed in teardown, and the missing cases have tests. Mutation checks (rule removed, guard removed) fail as expected.

## Root Cause

The CSS test was written for the stacking requirement only and the rest of the UI contract was left to the unfinished browser tasks; the AGENTS.md testing rules for parsers, negative assertions and move tests were not applied to the new files.

## Prevention

- Every row of a UI contract table has a test that fails when the rule is deleted; run each deletion once.
- A source-scanning test helper has a throw test for each construct it does not model (selector commas in parentheses, nested at-rules, `url()`, case).

**Promoted to**: Not yet
