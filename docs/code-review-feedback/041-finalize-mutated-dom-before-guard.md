# CRF-041: Finalize mutated the DOM before the guard that could reject it

**Date**: 2026-10-17
**Source**: Local AI review (spec review: errors agent, `specs/077-fix-dashboard-health-report-error/review.md`)
**Feature**: branch `bugfix/077-fix-dashboard-health-report-error`
**Files**: assets/javascripts/project_health/ai_helper_project_health.js, test/javascript/project_health/ai_helper_project_health.test.js
**Category**: error-handling
**Related**: CRF-003, CRF-022

## Feedback

In `finalizeStreamingContent`, the `updateHiddenReportContent` guards (result area is an HTMLElement, has a `.ai-helper-project-health-content` ancestor) ran only after `resultDiv.innerHTML` had already been replaced with the finished report. When a guard failed, the pane looked complete while the history refresh, export links and timestamp update — all after the throw — never ran. The two guards also carried the identical error message, so the failure reason was indistinguishable.

## Original Code

```js
function finalizeStreamingContent(resultDiv, parser, content) {
  const formattedContent = parser.parse(content);
  const finalHTML = '<div class="ai-helper-final-content">' + formattedContent + '</div>';
  resultDiv.innerHTML = finalHTML;

  // Store the markdown content in hidden field for PDF generation
  updateHiddenReportContent(resultDiv, content);
```

## Fix

The ancestor lookup moved into a `hiddenFieldContainerOf(resultDiv)` helper that throws a distinct message per failed condition. `finalizeStreamingContent` calls it before any DOM mutation; `updateHiddenReportContent` reuses it. A test detaches the result area before the stop event and asserts the guard throws while the result area still shows the loader; two more tests pin each distinct message.

## Root Cause

The guards were added in the same change as the structural requirement they enforce, but they were placed at the top of the callee (`updateHiddenReportContent`) instead of the top of the whole finalize sequence. The AI reasoned per-function ("the callee validates its input") and not per-operation ("validate everything that can reject the operation before its first side effect"). The existing test only asserted that the error propagated, not what state the page was left in.

## Prevention

A guard that can reject an operation must execute before that operation's first DOM or state mutation, at the top of the operation's entry point, with a distinct message per failed condition. For every such guard, add a test that makes it fail and asserts the earlier mutation did not happen, not just that the error was thrown.

**Promoted to**: Not yet
