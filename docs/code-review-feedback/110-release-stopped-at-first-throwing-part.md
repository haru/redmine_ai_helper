# CRF-110: Releasing a render stopped at the first part whose destroy threw

**Date**: 2026-11-21
**Source**: GitHub Copilot (PR #574)
**Feature**: branch `bugfix/088-fix-issue-form-rerender` / PR #574
**Files**: assets/javascripts/autocompletion/ai_helper_issue_autocompletion.js, test/javascript/autocompletion/ai_helper_issue_autocompletion.test.js
**Category**: error-handling
**Related**: CRF-095, CRF-098, CRF-106

## Feedback

If `autoCompletion.destroy()` throws, `releaseEntry()` skips the typo checker, the duplicate-check abort and the assignee suggestion. `releaseDetached()` has already removed the entry from the registry, so later scans never release them: the requests and listeners leak. Run every independent cleanup and rethrow the collected errors.
(<https://github.com/haru/redmine_ai_helper/pull/574#discussion_r4650857024>)

## Original Code

```js
if (entry.autoCompletion) {
  entry.autoCompletion.destroy();
}
if (entry.typoChecker) {
  entry.typoChecker.destroy();
}
// ... duplicate-check abort, assignment suggestion
```

## Fix

Each part is released inside its own `try`; the errors are collected and rethrown after all parts ran (the error itself for one failure, an `AggregateError` for several). The existing throwing-destroy test now asserts that the typo checker, the duplicate-check controller and the assignee suggestion were released, and a new test drives two failing parts.

## Root Cause

CRF-106 had already made the release path idempotent (remove the registration first, rethrow once) and its prevention rule says to keep independent later steps running with try/finally. The AI applied that to `start()` but wrote `releaseEntry()` as a plain sequence of calls, treating "remove from the registry first" as sufficient. It did not follow the consequence: removing first means the release gets exactly one chance, so every part has to run in that one call. The test only asserted that the error surfaced once, not that the other parts were released.

## Prevention

A teardown that releases several independent resources runs every release even when an earlier one throws, collects the errors and rethrows them after the last release (AggregateError for more than one). This is mandatory whenever the owner is unregistered before the teardown runs. Its test makes one release throw and asserts that every other resource was released.

**Promoted to**: AGENTS.md
