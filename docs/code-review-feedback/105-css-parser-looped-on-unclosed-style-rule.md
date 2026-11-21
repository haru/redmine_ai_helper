# CRF-105: CSS test parser looped forever on an unclosed style rule

**Date**: 2026-11-21
**Source**: GitHub Copilot (PR #572)
**Feature**: branch `bugfix/087-fix-popup-oc-colors` / PR #572
**Files**: test/javascript/support/css_rules.js, test/javascript/support/css_rules.test.js
**Category**: test-gap
**Related**: CRF-033, CRF-084, CRF-102

## Feedback

`end` can be `-1` for an unclosed ordinary style rule. `state.index = end + 1`
then resets the scan to offset 0, so `parseRules("a { b: c")` loops forever
instead of throwing, contrary to the helper's contract and its malformed-CSS
tests.
(https://github.com/haru/redmine_ai_helper/pull/572#discussion_r4649503153)

## Original Code

```js
} else {
  const end = css.indexOf("}", open);
  const body = css.slice(open + 1, end);
  ...
  state.index = end + 1;
}
```

## Fix

`enterBlock` throws `Unclosed rule: <prelude>` when `end === -1`, the JSDoc
list of rejected constructs names the unclosed style rule, and
`css_rules.test.js` adds `["an unclosed style rule", "a { b: c"]` to the
malformed-CSS table. Before the guard, the new case hung the Vitest worker
until it aborted.

## Root Cause

The helper was written to the CRF-033 rule (throw on unmodelled constructs),
and the unclosed cases were handled where a dedicated routine already existed:
`skipBlock` for `@keyframes` and the end-of-scan check for `@media`. The
ordinary style rule used a plain `indexOf("}")`, and its `-1` sentinel was not
checked because the malformed-input table was built per block kind that had
explicit closing logic, not per `indexOf` call. `-1 + 1 === 0` turned the
missing brace into a restart instead of an error, so no assertion could fail;
the test simply never existed.

## Prevention

In a source-scanning helper, every `indexOf`/search result used as an offset is
checked for `-1` before arithmetic on it, and the malformed-input test table
has one "unclosed" case for each block kind the scanner enters (style rule,
each at-rule), not only the ones with a dedicated skip routine.

**Promoted to**: Not yet
