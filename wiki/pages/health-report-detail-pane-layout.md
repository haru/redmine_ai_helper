---
title: Health Report Detail Pane Layout
type: decision
sources: [S048]
updated: 2026-10-15
---

# Health Report Detail Pane Layout

ADR-056 / feature 075 (GitHub issue #515): on the dashboard (width above
900px) the end of a long [Project Health Report](./health-report.md), the
frame's scrollbar bottom and the PDF/Markdown export links were clipped (S048).
Pure CSS fix in `assets/stylesheets/ai_helper.css`; no DB, Ruby, ERB or JS change (S048).

## Cause

- The dashboard height rules were written for `.ai-helper-health-report-detail`,
  a wrapper that exists only in the *placeholder* shown before any report is
  generated. A selected report's DOM is `.ai-helper-detail-pane >
  #ai-helper-health-report-detail-container > .ai-helper-health-report-body >
  [meta, edit link, frame, export links]` (S048).
- `.ai-helper-health-report-body` is not a flex container, so the frame's
  `max-height: 100%` resolved to the whole wrapper height without subtracting
  the meta block above it; the overflow was hidden by the pane's
  `overflow: hidden`. At 1280×800 the export links were cut off by 150px (S048).

## Decision

- Move the viewport-height cap from the pane to the frame:
  `.ai-helper-project-health-content.has-report` gets
  `max-height: max(17em, calc(100vh - 340px - 14em))` and `min-height: 17em`
  (about 10 lines). `340px` = pane top offset + bottom margin; `14em` = typical
  fixed part around the frame (S048).
- The pane has no `max-height`/`overflow: hidden`; it wraps its content with
  `align-self: flex-start` so it is not stretched to the history pane's height
  (reset to `auto` at ≤900px, where the layout is a column) (S048).
- While the edit form is open (`:has(> .ai-helper-health-report-edit-form:not([hidden]))`)
  the frame's `max-height` is removed so the save button and links are reachable
  (S048).
- At ≤900px the pre-fix values stay (`min-height: 360px`, no max-height) (S048).
- Dashboard-only flex rules that only passed height down were deleted (S048).

## Gotchas

- `14em` is an estimate: a growing fixed part (e.g. a ~45px flash notice after
  saving) pushes the pane past the viewport bottom, but nothing is hidden — the
  page scrolls (S048).
- jsdom computes no layout, so the contract is checked by a Vitest test that
  scans the CSS source, as in ADR-041:
  `test/javascript/project_health/ai_helper_health_report_layout_css.test.js` (S048).

## Alternatives rejected

- Vertical flex body + keep the pane cap: at 1280×600 the frame's minimum height
  collides with the cap and everything below 649px stays hidden (S048).
- A floor on the pane cap (`max(calc(100vh - 340px), 36em)`): a constant floor
  hides content again when the fixed part is larger; a bigger floor overflows
  even at 1280×800 (S048).
- `min-height: min-content` on the pane: Chromium treats block-axis
  `min-content`/`fit-content`/`max-content` as `auto` (no effect) (S048).
- Grid `fit-content()`: both block-axis contributions equal the full content
  height (S048).
- JavaScript height calculation: CSS alone suffices (S048).

## Related

[Project Health Report](./health-report.md) ·
[Health Report Editing](./health-report-editing.md) ·
[Health Report Markdown Rendering](./health-report-markdown-rendering.md) ·
[JavaScript Quality Tooling](./js-quality-tooling.md)
