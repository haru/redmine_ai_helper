# CRF-045: Finalize accepted a result area detached together with its whole pane

**Date**: 2026-10-17
**Source**: GitHub Copilot (PR #526)
**Feature**: branch `bugfix/077-fix-dashboard-health-report-error` / PR #526
**Files**: assets/javascripts/project_health/ai_helper_project_health.js, test/javascript/project_health/ai_helper_project_health.test.js, wiki/pages/health-report-generation-completion.md
**Category**: edge-case
**Related**: CRF-041

## Feedback

https://github.com/haru/redmine_ai_helper/pull/526#discussion_r4301053498

The structural guard in `finalizeStreamingContent` (`resultDiv.closest('.ai-helper-project-health-content')`) still accepts a result area whose whole report body was detached from the document: `closest()` finds the ancestor inside the detached subtree. This happens when `AiHelperMasterDetail#renderReportDetail` replaces the detail container's `innerHTML` while a generation is streaming; the stop event then finalizes the invisible old pane, and the hidden-field lookup by id (`document.getElementById`) can overwrite the newly shown pane's field.

## Original Code

```js
function finalizeStreamingContent(resultDiv, parser, content) {
  hiddenFieldContainerOf(resultDiv);

  const formattedContent = parser.parse(content);
  ...
  resultDiv.innerHTML = finalHTML;
  updateHiddenReportContent(resultDiv, content);
```

## Fix

`finalizeStreamingContent` checks `resultDiv.isConnected` after the structural guard. When the result area is detached it skips the body, hidden field, export links and metadata, and only calls `refreshHealthReportHistory()` (the report was saved on the server). Closing the stream on pane replacement was rejected because it could stop server-side generation. A test detaches the whole pane mid-stream, inserts a new pane with its own hidden field, and asserts the old pane is not finalized, the new field is untouched and the history refresh still runs. The wiki page records the decision.

## Root Cause

CRF-041's regression test detached only the result area from its content container, so the AI modelled "structure broken" as "ancestor missing". It did not list the other ways the element the stream captured at click time can stop being the one on screen — the asynchronous detail-pane reload in `ai_helper_master_detail.js` replaces the whole subtree, which keeps every ancestor relation intact. Long-lived callbacks (EventSource handlers) holding a DOM reference were not checked against the code paths that replace that DOM while they run.

## Prevention

When an asynchronous callback (stream handler, timer, fetch continuation) writes into a DOM element captured before it started, grep for every code path that can replace that element or one of its ancestors (`innerHTML =`, `replaceWith`, `remove`) during the wait, and decide explicitly what the callback does when `element.isConnected` is false. Ancestor checks (`closest`) do not detect a detached subtree; add a test that detaches the whole subtree, not only the element.

**Promoted to**: Not yet
