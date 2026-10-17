# CRF-046: SSE try block wrapped reading the event data, not only the parse

**Date**: 2026-10-17
**Source**: GitHub Copilot (PR #526)
**Feature**: branch `bugfix/077-fix-dashboard-health-report-error` / PR #526
**Files**: assets/javascripts/project_health/ai_helper_project_health_actions.js, test/javascript/project_health/ai_helper_project_health_actions.test.js, wiki/pages/health-report-generation-completion.md
**Category**: error-handling
**Related**: CRF-014, CRF-022

## Feedback

https://github.com/haru/redmine_ai_helper/pull/526#discussion_r4301053528

The `try` meant to cover only `JSON.parse` also evaluated `event.data`, so a `SyntaxError` raised by a throwing data getter was treated as a recoverable parse failure, and the logger read `event.data` a second time. The comment above the catch claimed a throwing getter would surface, which was not true for `SyntaxError`.

## Original Code

```js
try {
  data = JSON.parse(event.data);
} catch (error) {
  // ... Anything else — including a throwing event.data getter — is a real
  // bug and must surface.
  if (error instanceof SyntaxError) {
    console.error('Failed to parse project health streaming event data:', error, event.data);
    return;
  }
  throw error;
}
```

## Fix

`const rawData = event.data;` is read once before the `try`; only `JSON.parse(rawData)` is inside it and the log prints `rawData`. Tests: a getter that throws `SyntaxError` on its first read only must propagate without logging (the old code swallowed it because the logger's second read succeeded), and the data getter is read exactly once per message.

## Root Cause

The AI narrowed the catch by error class (`SyntaxError`) but not by the expression range of the `try`, assuming the argument expression `event.data` cannot throw. It then wrote a comment stating the intended behaviour without checking it against the error-class filter. The existing test used a getter throwing `TypeError`, which passed for the wrong reason and hid the gap.

## Prevention

A `try` (JS) or `begin`/`rescue` (Ruby) that turns an error into a log-and-continue result contains only the single call whose errors are expected; evaluate its arguments into locals before the block and log those locals, never re-read the source in the handler. Test the filter with an error of the *handled* class raised outside that call, not only with an unhandled class.

**Promoted to**: Not yet
