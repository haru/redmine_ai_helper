# CRF-034: Layout CSS test re-parsed the stylesheet per lookup and duplicated selector constants

**Date**: 2026-10-15
**Source**: Local AI review (`/speckit-review-run`, simplify and comments agents)
**Feature**: branch `bugfix/075-fix-health-report-clipping`
**Files**: test/javascript/project_health/ai_helper_health_report_layout_css.test.js
**Category**: readability
**Related**: CRF-012, CRF-018

## Feedback

- `findRules` called `getRules()` on every lookup, reading and scanning the CSS file about ten times.
- The `pane` and `frame` selectors were defined in two `describe` blocks.
- The C-3 contract test sat in a `describe` named "scan helpers", so contract IDs and describe blocks did not line up.

## Original Code

```js
function findRules(selector, { media }) {
  return getRules().filter(...);
}
```

## Fix

Parse once into a module-level `RULES`; move `PANE` and `FRAME` next to `D`; put C-3 in its own "unchanged unscoped rules (C-3)" describe.

## Root Cause

The AI grew the test incrementally per contract item and did not re-read the file as a whole before finishing.

## Prevention

- Before finishing a test file, check that each `describe` title matches the contract IDs it contains, and hoist values defined in more than one block.

**Promoted to**: Not yet
