# CRF-047: Saved-report swap and chart loading failed silently in the browser

**Date**: 2026-10-17
**Source**: Local AI review (speckit-review-run, 6 parallel agents)
**Feature**: branch `feature/078-health-report-charts` (fix not yet committed)
**Files**: assets/javascripts/project_health/ai_helper_project_health.js, ai_helper_project_health_actions.js, ai_helper_project_health_swap.js, ai_helper_health_report_chart.js
**Category**: error-handling
**Related**: CRF-036, CRF-041, CRF-046

## Feedback

- `finalizeStreamingContent` returned the swap promise, but its only caller dropped it: a 403/404/500 or network error left a finished-looking client-rendered body without charts or export links, with only an unhandled rejection in the console.
- The content-url meta check ran after the result area had already been rewritten (the CRF-041 shape).
- `health_report_saved`'s `report_id` was not validated, so a malformed event silently fell back to the client render.
- `addReportExportLinks` returned silently when the content root or its URLs were missing, and built `href="#"` links for a single missing URL.
- `loadChart()` had no rejection handler; the canvas was already marked rendered, so it stayed blank forever.

## Original Code

```js
finalizeStreamingContent(resultDiv, parser, content, savedReportId); // promise dropped
...
if (!contentRoot) { return; }
if (!markdownUrl && !pdfUrl) { return; }
...
loadChart().then(function (loaded) { new loaded(canvas, config); });
```

## Fix

`savedReportContentUrl()` validates the id (positive integer) and the meta tag before `finalizeStreamingContent` touches the DOM. The caller attaches `.catch` and `showSavedReportSwapError` renders the error message (built with `createElement`/`textContent`) and logs the cause. `savedReportIdOf()` throws on a bad `report_id`. `addReportExportLinks` throws on a missing root or URL. A failed `loadChart()` clears the rendered mark and logs. Tests drive every new branch.

## Root Cause

The AI wrote the promise-returning function and tested it in isolation (the promise rejects), but never followed the promise to its caller, so nobody handled the rejection in the real flow. The guards were written as "nothing to do" early returns modelled on older DOM helpers, without asking whether the missing element meant a contract violation. CRF-041 was in the index but was applied only to the guards that existed before this change, not to the newly added meta lookup.

## Prevention

- Every promise a function returns is either returned again or ends in a `.catch` that shows the failure to the user; test the caller with a rejecting stub, not only the callee.
- Every lookup that can fail (meta tag, id, response structure) happens before the first DOM write of the function (CRF-041 applies to new guards too).
- An element or attribute that the server's own template always emits is required: throw when it is missing instead of returning or substituting `#`.

**Promoted to**: Not yet
