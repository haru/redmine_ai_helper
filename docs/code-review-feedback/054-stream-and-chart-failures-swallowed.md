# CRF-054: Stream completion, swap and chart failures were swallowed or invisible in the browser and the controller

**Date**: 2026-10-17
**Source**: Local AI review (speckit-review-run, 6 parallel agents)
**Feature**: branch `feature/078-health-report-charts` (fix not yet committed)
**Files**: assets/javascripts/project_health/ai_helper_comparison.js, ai_helper_project_health_actions.js, ai_helper_health_report_chart.js, app/controllers/ai_helper_controller.rb
**Category**: error-handling
**Related**: CRF-014, CRF-022, CRF-027, CRF-046, CRF-047

## Feedback

- `ai_helper_comparison.js` wrapped the whole `onmessage` in a bare `catch {}`: a render failure of the final frame (the `replaceForComparison` TypeError or a parser exception) was discarded, leaving the cursor frame stuck without exports or console output. `eventSource.close()` had already run, so `onerror` never fired.
- An invalid `health_report_saved` SSE event made `savedReportIdOf`'s throw go to `window.onerror` only; the stream continued into the chartless client-rendered path — exactly what CRF-047 was meant to prevent.
- A synchronous throw by `finalizeStreamingContent` was never seen by `.catch` (which only sees a rejected return promise), so the stream stopped with no user-visible message.
- `loadChart().then(onFulfilled, onRejected)` does not catch exceptions thrown inside `onFulfilled`: a missing `default` export or a throwing Chart constructor became an unhandled rejection, the canvas kept its drawn marker (no retry), and the user saw a blank chart.
- One invalid canvas aborted the loop, so every later chart on the page stayed blank.
- When the saved report's body did not match the generated one, `send_health_report_saved_event` sent no event and logged nothing, indistinguishable from an LLM error (CRF-014/022 rule).

## Original Code

```js
} catch (error) { /* final-frame render errors discarded */ }
...
loadChart(canvas, payload).then(drawChart, showChartError);
```

## Fix

Every `JSON.parse` guard is now SyntaxError-only (log and keep receiving; everything else rethrows). The saved-report record captures the event-read failure and `finishGeneration` reports event failures, synchronous throws and rejected swap promises through `showSavedReportSwapError`. Chart loading is `.then().catch()`, marks the canvas with `data-ai-helper-chart-failed`, shows a visible `p.warning` built with `textContent` (message from the wrapper's `data-chart-error-message`, fixed fallback), and isolates failures per canvas. The controller logs a warning with the report id and project id on the body mismatch.

## Root Cause

CRF-047 fixed this pattern in one file (`ai_helper_project_health_actions.js`); the same idioms in its sibling files (`comparison.js`, the chart loader) and in the controller path were not re-checked against it. `.then(onFulfilled, onRejected)` was treated as equivalent to `.then(onFulfilled).catch(onRejected)`, which it is not.

## Prevention

After fixing a swallow-or-silent failure in one file, grep the sibling files and the server side of the same feature for the same idiom (bare `catch {}`, whole-handler `try`, `.then(f, r)`) in the same change, and fix them together. Guard only the call that can actually throw, and let render/save failures reach a user-visible reporter.

**Promoted to**: Not yet
