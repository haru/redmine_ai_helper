# CRF-061: Late async work in the browser acted on targets that had been replaced or reused

**Date**: 2026-10-18
**Source**: GitHub Copilot (PR #528)
**Feature**: branch `feature/078-health-report-charts` / PR #528 (fix not yet committed)
**Files**: assets/javascripts/project_health/ai_helper_project_health_swap.js, assets/javascripts/project_health/ai_helper_project_health_actions.js, assets/javascripts/project_health/ai_helper_health_report_chart.js, eslint.config.js, test/javascript/project_health/ai_helper_project_health_actions.test.js, test/javascript/project_health/ai_helper_health_report_chart.test.js
**Category**: edge-case
**Related**: CRF-045, CRF-049

## Feedback

- A delayed swap from generation A could overwrite generation B, because a new generation reuses the same connected result element: A's response replaced B's loader or body and installed A's export links, and A's rejection replaced B with an error box (https://github.com/haru/redmine_ai_helper/pull/528#discussion_r4305466655).
- The MutationObserver drew added canvases but never destroyed Chart.js instances for removed ones, so selection, edit saves and previews accumulated detached charts; a delayed `import("chart.js")` could also draw on a canvas already removed (https://github.com/haru/redmine_ai_helper/pull/528#discussion_r4305466647).

## Original Code

```js
if (!resultDiv.isConnected) {
  return;
}
resultDiv.innerHTML = html;
```

```js
new ChartClass(canvas, config);
```

## Fix

- Each generation stamps the result area (`beginReportGeneration`, `data-ai-helper-generation`); the swap and its failure handler apply only when the stamp is unchanged. A regression test resolves two generations' requests in reverse order, and covers a newer generation still streaming and an older failure.
- Chart instances are kept per canvas; on removals the observer destroys those whose canvas is no longer connected, and the dynamic-import path skips a canvas that left the document. Tests cover subtree removal, `innerHTML` replacement, kept siblings, single destroy, the import path and removal before the import resolved.

## Root Cause

CRF-045 taught "check `isConnected` after an await", and the code applied exactly that; but `isConnected` only detects replacement of the element, not reuse of the same element by a newer operation. For the charts, the observer was written for the "add" half only; the lifecycle of the third-party object it creates (Chart.js requires `destroy()`) was not considered.

## Prevention

- An async continuation that writes into a long-lived element must check ownership, not just presence: capture a token when the operation starts and compare it when it settles (both success and failure). Test with two operations settled in reverse order.
- Code that creates objects with an explicit release API (`destroy`, `disconnect`, `close`) in response to DOM additions must also release them on removal, and must not create them after an await if the target is gone.

**Promoted to**: Not yet
