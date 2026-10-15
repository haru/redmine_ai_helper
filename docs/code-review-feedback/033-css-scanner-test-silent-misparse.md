# CRF-033: CSS source-scan test misparsed unsupported constructs silently and had bypassable negative checks

**Date**: 2026-10-15
**Source**: Local AI review (`/speckit-review-run`, tests, code and simplify agents)
**Feature**: branch `bugfix/075-fix-health-report-clipping`
**Files**: test/javascript/project_health/ai_helper_health_report_layout_css.test.js
**Category**: test-gap
**Related**: CRF-024, CRF-029, CRF-003

## Feedback

- The scanner treated `@keyframes` preludes as rules (depth went negative and media tracking was right only by accident), turned `@supports (…) { … }` into a fake rule that swallowed its contents, and attributed rules after a nested `@media` to no media. The "no `max-height` / no `overflow: hidden`" checks could therefore pass falsely.
- Selector lists were split at every comma, breaking `:is(a, b)`; merging ignored `!important`; selectors and values were compared with exact spacing around `>`, `,` and `(`.
- Negative checks used `not.toBe("hidden")` (missing `clip`, `hidden !important`, two-value `overflow`), C-1.2 did not check `overflow-y`, and both looked only at rules outside `@media`.
- "tracks the media query of a rule" only asserted that some rule existed; R-006 would pass vacuously if media tracking broke.

## Original Code

```js
const selectors = prelude.split(",").map(...);
expect(d.overflow).not.toBe("hidden");
```

## Fix

The scanner takes a source string, skips `@keyframes`, throws on any other at-rule, nested `@media`, nested rules and unbalanced braces, splits selectors at top-level commas and normalizes spacing. `merge` keeps `!important` values. A shared `expectNoClipping` checks `max-height` and `overflow`/`overflow-x`/`overflow-y` against `hidden|clip` in every media context. Scanner behaviour has its own tests on synthetic CSS; R-006 asserts the narrow block is found.

## Root Cause

The AI wrote just enough scanner to pass on the current stylesheet and verified it only against that file. It did not ask which edits to the stylesheet would make a negative assertion pass without the contract holding, and it let the scanner fall back to a best guess on input it did not understand, against the AGENTS.md "no fallback" rule.

## Prevention

- A test helper that parses source (CSS, templates, config) throws on any construct it does not model, and that throw has a test.
- For every negative assertion ("X is absent"), list the equivalent spellings of X (keywords, `!important`, shorthands, other media/at-rule contexts) and cover them, plus one assertion that the searched region was found at all.

**Promoted to**: AGENTS.md
