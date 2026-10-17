---
title: Health Report Generation Completion (Dashboard)
type: decision
sources: [S050]
updated: 2026-10-17
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
- Export links are **not** added by this path in the dashboard: `addPdfExportButton`
  is unchanged; the id-bearing links arrive when the detail pane reloads after
  completion (S050).
- No ADR: a small local fix, not an architectural decision (S050).

## Rejected alternatives

- Append the field to `document.body`: detached from the widget and duplicated on
  pane reload (S050).
- Add `.ai-helper-project-health` to the dashboard ERB: reuses a class that
  triggers `addPdfExportButton` and other unintended behavior (S050).
- Do nothing when the wrapper is missing: loses the export body the overview needs
  (S050).
- Keep `catch` but only `console.error(error)`: still hides the cause (S050).
- Rebuild the detail pane via `innerHTML`: violates "no HTML built in JS" (S050).
- Disabling the generate link while the edit form is open (FR-009): withdrawn
  because Redmine has no generic disabled-link class; opening generation with the
  form open drops the unsaved input (S050).

## Gotchas

- The selected row in the history list stays `selected` on the previous report
  during generation; after completion the top row is selected (S050).
- Existing test DOM helper always created `.ai-helper-project-health`, which is why
  the bug was not reproduced before; tests now use a detail-pane structure without
  it (S050).

## Related

[Project Health Report](./health-report.md) ·
[Health Report Detail Pane Layout](./health-report-detail-pane-layout.md) ·
[Health Report Editing](./health-report-editing.md)
