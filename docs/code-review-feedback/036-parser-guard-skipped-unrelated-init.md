# CRF-036: Early return for a missing Markdown parser silently skipped initialization that no longer needed it

**Date**: 2026-10-16
**Source**: Local AI review (`/speckit-review-run`, errors agent)
**Feature**: branch `bugfix/076-fix-health-report-table-style`
**Files**: assets/javascripts/project_health/ai_helper_project_health.js, test/javascript/support/dom_content_loaded.js
**Category**: error-handling
**Related**: CRF-003

## Feedback

After the change, `initializeExistingReportDisplay()` no longer used `AiHelperMarkdownParser`, yet the `DOMContentLoaded` handler still returned silently (no log) when the parser was missing or its constructor threw, before the `has-report` class, the PDF button, the observer and the export click handler were set up.

## Original Code

```js
let parser;
try {
  if (typeof AiHelperMarkdownParser !== 'undefined') { parser = new AiHelperMarkdownParser(); }
  else { return; }
} catch { return; }
initializeExistingReportDisplay();
```

## Fix

Parser-independent initialization runs first. A missing parser then throws an `Error` before the generate-click handler is registered, and the `DOMContentLoaded` test helper removes the listeners registered so far when a handler throws.

## Root Cause

The AI removed the parser argument from one function but left the surrounding guard as it was, and did not re-check which of the following statements still depended on it. The guard was a silent fallback, which AGENTS.md forbids.

## Prevention

- When a change removes a dependency from a function, re-read the guards around its call site and move every statement that no longer needs that dependency out of the guarded region.
- A guard for a missing script or object throws; it does not `return` or swallow the error in an empty `catch`.

**Promoted to**: Not yet
