# CRF-043: Comments described narrower scopes than the code they annotate

**Date**: 2026-10-17
**Source**: Local AI review (spec review: comments agent, `specs/077-fix-dashboard-health-report-error/review.md`)
**Feature**: branch `bugfix/077-fix-dashboard-health-report-error`
**Files**: assets/javascripts/project_health/ai_helper_project_health.js, assets/javascripts/project_health/ai_helper_project_health_actions.js, test/javascript/project_health/ai_helper_project_health_actions.test.js
**Category**: doc-comment
**Related**: CRF-005, CRF-011, CRF-028

## Feedback

- The `catch` comment claimed it covered "only JSON.parse failures", while the `try` also covers reading `event.data` (a throwing getter is re-thrown, not logged).
- Two comments said the detail-pane cleanup is a no-op "outside a detail pane (project overview)", but the dashboard placeholder is a second no-op layout.
- The hidden-field JSDoc said `.ai-helper-project-health` is missing "in the dashboard detail pane", though it is missing on the whole dashboard tab.
- A test comment referred to "data-model.md" without the path.

## Fix

The catch comment now names both covered operations (reading `event.data`, parsing it) and that only `SyntaxError` is swallowed; the no-op comments name both layouts (project overview, dashboard placeholder); the JSDoc says the whole dashboard tab lacks the wrapper; the test comment cites `specs/077-fix-dashboard-health-report-error/data-model.md`.

## Root Cause

The comments were written from the intent at authoring time and then never re-read against the final code: the `try` block had grown to cover the argument evaluation, and the layouts list was copied from the first place the code ran instead of grepping the views for the selector.

## Prevention

When writing a scope claim (what a catch covers, which layouts a branch reaches, where a selector exists), verify it in the same step against the code block or the templates (`grep` the selector across `app/views/`), and reference repo documents by path from the repo root.

**Promoted to**: Not yet
