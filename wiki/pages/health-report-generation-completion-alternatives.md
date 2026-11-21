---
title: Health Report Generation Completion: Alternatives & Gotchas
type: decision
sources: [S050]
updated: 2026-11-21
---

# Health Report Generation Completion: Alternatives & Gotchas

Rejected alternatives and gotchas. Split from [Health Report Generation Completion (Dashboard)](./health-report-generation-completion.md).

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

- [Health Report Generation Completion (Dashboard)](./health-report-generation-completion.md) — the main page.
