# CRF-106: Issue form aids swallowed attach errors and left half-released state behind

**Date**: 2026-11-21
**Source**: Local AI review (speckit-review-run, 6 agents)
**Feature**: branch `bugfix/088-fix-issue-form-rerender`
**Files**: assets/javascripts/autocompletion/ai_helper_issue_autocompletion.js, assets/javascripts/autocompletion/ai_helper_assignment_suggestion.js
**Category**: error-handling
**Related**: CRF-003, CRF-054, CRF-095, CRF-098

## Feedback

- `scan()` caught every attach error and only called `console.error`, a silent fallback that AGENTS.md forbids.
- When `releaseEntry` threw inside the attach rollback, it replaced the original error; when it threw while releasing a detached render, the entry stayed in the registry and threw again on every mutation.
- The duplicate-check click listener of an entry whose attach failed stayed live and started a request nobody could abort.
- `dataset.config || '{}'` turned a missing config attribute into an empty config (CRF-050 boundary input); a persisted issue's missing notes controls were skipped by an `if`.
- A non-OK duplicate-check response with an HTML body threw a `SyntaxError` from `response.json()`.

## Original Code

```js
try { attach(overlay); } catch (error) {
  failedOverlays.add(overlay);
  console.error('ai_helper: failed to attach ...', error);
}
const config = JSON.parse(overlay.dataset.config || '{}');
```

## Fix

`scan` records the container before attaching and lets the error propagate; `start()` still attaches the notes aids and the observer (try/finally) and rethrows. The rollback throws an `AggregateError` when releasing fails too; entries leave the registry before release; entries carry a `released` flag checked by the click handler; missing `data-config` / `data-assignment-config` / notes controls throw; non-JSON error responses report the HTTP status.

## Root Cause

The AI copied the "report once and carry on" idiom of ADR-070's `failedForms` and justified it with "one broken render must not block the others", although only one config container exists per render. It checked CRF-098 for the rollback but not what happens when the rollback itself fails, and it did not consult the "never implement fallback error handling" and CRF-050 boundary-input rules for the `|| '{}'` defaults.

## Prevention

When a rollback or release path can itself throw, make it idempotent: remove the registration before releasing, keep the original error (AggregateError), and mark the entry released so listeners that outlive it do nothing. A catch that only logs is a fallback: record the failure state, then let the error propagate, and keep independent later steps running with try/finally. Data attributes rendered by ERB are boundary input: a missing one throws.

**Promoted to**: Not yet
