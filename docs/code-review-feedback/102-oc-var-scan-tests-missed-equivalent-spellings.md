# CRF-102: Open Color scan tests missed equivalent spellings and unmodelled CSS

**Date**: 2026-11-21
**Source**: Local AI review (speckit-review-run: tests, errors)
**Feature**: branch `bugfix/087-fix-popup-oc-colors`
**Files**: test/javascript/support/open_color_vars.js, test/javascript/support/css_rules.js, test/javascript/shared/ai_helper_redmine_version_colors_css.test.js
**Category**: test-gap
**Related**: CRF-033, CRF-084

## Feedback

The "every `var(--oc-*)` has a fallback" check searched the raw text for the exact
string `var(--oc-`. `var( --oc-x)`, a newline after `var(`, `VAR(--oc-x)` and a
space before the comma escaped it (the reviewer confirmed this by editing the CSS).
In the CSS parser, a comma inside nested parentheses (`:is(:not(.a), .b)`) was
misread without throwing, a property declared twice in one rule silently kept the
last value, and `var(--oc-*)` inside `@keyframes` was never checked. Comments were
scanned as if they were declarations.

## Original Code

```js
const OPEN_COLOR_VAR = "var(--oc-";
let index = source.indexOf(OPEN_COLOR_VAR);
// ...
if (/\([^)]*,/.test(prelude)) { throw ... }   // only the first parenthesis group
```

## Fix

- `open_color_vars.js` matches `/var\(\s*--oc-/i`, accepts whitespace before the
  comma, and ignores CSS comments.
- `splitSelectors` counts parenthesis depth and throws on a comma at any depth > 0
  and on unbalanced parentheses.
- `parseDeclarations` throws on a property declared twice; `@keyframes` bodies that
  contain `var(--oc-*)` throw.
- Every new case was added to the throw tables first and failed before the fix.
- Fix commit: not committed yet (working tree of the branch).

## Root Cause

The AI reused the first spelling it saw as the whole pattern, and wrote the
throw guard for the simplest shape of the construct. AGENTS.md already says
negative assertions cover equivalent spellings (CRF-033) and parsers throw on
constructs they do not model (CRF-024); the AI applied those rules to the cases
it thought of but did not enumerate the CSS grammar for the construct (function
name case, whitespace, nesting, repeated properties, at-rule bodies, comments).

## Prevention

When a test scans source for a construct, list its spellings from the language
grammar before writing the matcher (case, whitespace and newlines inside and
around it, nesting, repetition, comments, at-rule bodies) and put one row per
spelling into the helper's test table, for both the match and the throw cases.

**Promoted to**: Not yet
