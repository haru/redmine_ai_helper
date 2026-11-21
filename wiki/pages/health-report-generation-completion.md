---
title: Health Report Generation Completion (Dashboard)
type: decision
sources: [S050]
updated: 2026-11-21
---

# Health Report Generation Completion (Dashboard)

Feature 077 (GitHub issue #524): on the dashboard tab, finishing a streamed
[Project Health Report](./health-report.md) threw a TypeError and the history
list was never refreshed. Browser-side JS only; no Ruby, ERB, locale or CSS
change (S050).

## Cause

- `updateHiddenReportContent` appended the hidden `#ai-helper-health-report-content`
  field to `.ai-helper-project-health`, a wrapper that the dashboard tab does not
  have (it is used by the project overview), so `appendChild` ran on `null` and the
  steps after it (history refresh) never ran (S050).
- The `onmessage` `try/catch` wrapped the whole handler, so a real failure was
  logged as if it were a JSON parse problem (S050).
- Measured in the browser (S050): during streaming the detail pane still showed the
  previous report's creation time/author, edit link and export links pointing at
  that report's id. The post-completion console error itself was **not** measured
  in the browser (generation takes longer than 30 s); it was reproduced in Vitest.

## Decisions

- **Hidden field lives under `resultDiv.closest('.ai-helper-project-health-content')`**,
  found by one lookup; reused if it already exists; a missing container raises
  (no fallback). That container exists in all three layouts (overview, dashboard
  placeholder, dashboard detail pane) (S050).
- **Narrow the `try/catch` to `JSON.parse`** and handle only `SyntaxError`; other
  errors are rethrown, and post-parse work (`schedule()`, `finalizeStreamingContent`)
  runs outside the `try`. `eventSource.close()` is called before finalize on
  `finish_reason === 'stop'`, so a throwing finalize cannot cause a second message
  (S050).
- **On generation start in a dashboard detail pane, remove the previous report's
  details** (`.ai-helper-health-report-body` descendants: meta, `.contextual` edit
  link, edit form, original block + its toggle `<p>`, `.flash`, `.other-formats`)
  and un-hide the result area (and the view wrapper, hidden while the edit form is
  open) so the stream is visible. A no-op outside a detail pane (S050).
- **A result area detached from the document is not finalized.** Selecting another
  report while streaming replaces the whole detail pane, so the result area keeps
  its `.ai-helper-project-health-content` ancestor inside the detached subtree and
  passes the structural guard. `finalizeStreamingContent` checks
  `resultDiv.isConnected`; when detached it skips the body, hidden field, export
  links and metadata (the hidden-field lookup by id would otherwise overwrite the
  newly shown pane's field) and only refreshes the history list, since the report
  was saved on the server. The stream is not closed on pane replacement, because
  closing it could stop the server-side generation (PR #526 review).
- `onmessage` reads `event.data` once, before the `try`, so only `JSON.parse` is
  guarded and the logged payload is that saved value (PR #526 review).
- Export links are **not** added by the stream itself: after completion, feature
  078's swap fetches the saved report's server-rendered content and
  `addReportExportLinks` rebuilds the links from its data attributes into an
  `.other-formats` paragraph (id-less links to the saved report's own export
  endpoints; the POST-based `-dynamic` links added during generation are
  removed). `addPdfExportButton` is unchanged (S050; feature 078).
- No ADR: a small local fix, not an architectural decision (S050).

## Rejected alternatives & gotchas

Rejected alternatives and gotchas are on a separate page. See [Health Report Generation Completion: Alternatives & Gotchas](./health-report-generation-completion-alternatives.md) (S050).

## Related

[Project Health Report](./health-report.md) ·
[Health Report Detail Pane Layout](./health-report-detail-pane-layout.md) ·
[Health Report Editing](./health-report-editing.md)
