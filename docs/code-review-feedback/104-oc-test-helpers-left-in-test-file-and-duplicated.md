# CRF-104: Open Color test helpers lived in a test file and duplicated a scan loop

**Date**: 2026-11-21
**Source**: Local AI review (speckit-review-run: simplify)
**Feature**: branch `bugfix/087-fix-popup-oc-colors`
**Files**: test/javascript/shared/ai_helper_redmine_version_colors_css.test.js, test/javascript/chat/ai_helper_chat_popup_css.test.js, test/javascript/support/
**Category**: readability
**Related**: CRF-034, CRF-079

## Feedback

- The `var(--oc-*)` helpers were exported from a `*.test.js` file, and the
  `parseRules` self-tests stayed in the popup test after the parser moved.
- `resolveForRedmine6` and `resolveForRedmine7` used two different loops, and the
  "no usable fallback" check was spelled three times.
- The contract table repeated a selector literal, mixed spacing styles, read the
  stylesheet twice, and one test name was unclear.

## Original Code

```js
export function resolveForRedmine6(value) { /* re-scan from 0 after each splice */ }
export function resolveForRedmine7(value) { /* cursor-based loop */ }
```

## Fix

Moved the helpers and their tests to `support/open_color_vars.js` and
`support/css_rules.test.js`, added `mapOpenColorVars` and `hasFallback`, introduced
an `APPLY_BTN` constant, normalized the table spacing, read each stylesheet once
and renamed the test. Fix commit: not committed yet.

## Root Cause

The AI added the helpers where the first test needed them and wrote each resolver
independently. The earlier parser extraction moved the code but not its tests, and
no step checked where the second consumer would look for them.

## Prevention

When code moves out of a test file into `test/javascript/support/`, move its
self-tests in the same change; write helpers that walk the same text with one
shared walker, and name each repeated predicate once.

**Promoted to**: Not yet
