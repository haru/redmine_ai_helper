# CRF-042: Test DOM and assertions were derived from the code instead of the real markup

**Date**: 2026-10-17
**Source**: Local AI review (spec review: tests/simplify/errors agents, `specs/077-fix-dashboard-health-report-error/review.md`)
**Feature**: branch `bugfix/077-fix-dashboard-health-report-error`
**Files**: test/javascript/project_health/ai_helper_project_health_actions.test.js, test/javascript/project_health/ai_helper_project_health.test.js, test/javascript/support/dashboard_detail_pane.js
**Category**: test-gap
**Related**: CRF-024, CRF-029, CRF-033, CRF-035

## Feedback

- The previous-report tests only checked that `querySelector` returned null for each removed element, so a change that detached the whole pane (`reportBody.innerHTML = ''`) would still pass, while the browser rendered into a detached node.
- The test DOM put the "show original" link alone in its `<p>`, while the ERB renders both toggle links in one paragraph — a regression removing only the link instead of the paragraph was invisible.
- The dashboard "no report yet" state was never built from the real structure (`​.ai-helper-health-report-detail` > `.ai-helper-project-health-content` > `#result` + server-rendered hidden input) nor driven to the stop event.
- The finalize-error test never checked that the EventSource was closed (and the current-source reference dropped) before finalize ran, so moving `close()` after `finalizeStreamingContent` passed the suite.

## Fix

Removal tests now also assert `document.getElementById("ai-helper-project-health-result")` is the same node, `detailPane.contains(resultDiv)`, and that the toggle `<p>` is detached (`isConnected === false`); the helper renders both links in one `<p>` in both pane states (original shown / edit form open). A test drives the server-rendered no-report structure through a full generation and asserts one hidden field plus one `updateHealthReportHistory` call. The finalize-error test asserts `source.closed`, and — via a `closeCount` on the fake — that a later click does not close the failed stream again. Shared pane markup moved to `test/javascript/support/dashboard_detail_pane.js`; stop sends and two-generation sequences were extracted into `sendStop`/`generateReport` helpers; mock cleanup moved to `afterEach` (`vi.restoreAllMocks()`) so a failing assertion no longer leaks spies into the next test; a `"null"` payload test pins the not-an-object TypeError.

## Root Cause

The test fixtures were reverse-engineered from what the code under test touches, not copied from the production templates, and the assertions were written as "the thing is gone" checks without asking which mutation the suite must still catch (whole-pane detach, link-only removal, close-after-finalize). CRF-033's rule (a negative assertion must also assert the searched region was found) was applied to CSS scanning but not to DOM removal checks.

## Prevention

Build test DOM by transcribing the production ERB (same elements, classes, nesting, siblings) and, for every removal/cleanup assertion, name the concrete regression it must catch and assert the survivors: removed nodes are detached, kept nodes are still reachable from `document` by id or `contains`. Any state transition whose steps are ordered (close before finalize) needs a test that would fail if two adjacent steps swap.

**Promoted to**: Not yet
