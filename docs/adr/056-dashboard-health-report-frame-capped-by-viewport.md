# ADR-056: Cap the dashboard health report frame, not the pane, by viewport height

**Date**: 2026-10-15
**Status**: Accepted

## Context

On the dashboard (width above 900px), the health report detail pane was capped at `max-height: calc(100vh - 340px)` with `overflow: hidden`. The dashboard rules that passed the height down to the report frame were written for the `.ai-helper-health-report-detail` wrapper, but that wrapper only exists in the placeholder shown before a report is generated. In the DOM of a selected report (`.ai-helper-detail-pane > #ai-helper-health-report-detail-container > .ai-helper-health-report-body > [meta, links, frame, export links]`), `.ai-helper-health-report-body` is not a flex container. So the frame's `max-height: 100%` resolved to the full height of the body wrapper, without subtracting the meta information and the edit link above it.

On a 1280×800 viewport the body wrapper was 460px high and the frame 458px. The frame started 128px lower (meta 99px, edit link 29px), so its bottom 117px and the PDF / Markdown export links were cut off by the pane's `overflow: hidden` (the export links by 150px; GitHub issue #515). The frame's `min-height: 360px` did not cause this, since the frame was taller than that; it only decided the outcome at 1280×600. Details and measurements: `specs/075-fix-health-report-clipping/research.md` (R-001 to R-006).

## Decision

- The viewport-height cap moves from the pane to the report frame. `.ai-helper-project-health-content.has-report` gets `min-height: 17em; height: auto !important; max-height: max(17em, calc(100vh - 340px - 14em)); overflow-y: auto !important`. `340px` is the pane's top offset plus the bottom margin, `14em` is the typical fixed part around the frame (meta, links, pane padding and border) and `17em` keeps about 10 lines visible.
- The pane has no `max-height` or `overflow: hidden`; it wraps its content, with `align-self: flex-start`. The dashboard-only rules for the detail container, the detail element and the report body, which existed only to make flex children shrink, are removed.
- While the edit form is open (`:has(> .ai-helper-health-report-edit-form:not([hidden]))`), the frame's `max-height` is `none`, so the save button and the export links are reachable without scrolling inside the frame.
- At width 900px or below, the pre-fix values stay: `align-self: auto`, `min-height: 360px`, `max-height: none`.
- The layout contract is checked by a Vitest test that scans the CSS source, because jsdom computes no layout (`test/javascript/project_health/ai_helper_health_report_layout_css.test.js`).

## Consequences

- The export links and the "show original / edited" links stay inside the pane at any viewport height. On a short screen the pane grows below the viewport and the page scrolls (as for any page).
- `14em` is an estimate. When the fixed part grows, for example with a flash notice after saving (about 45px), the pane extends past the viewport bottom by that amount; nothing is hidden.
- The edit form no longer scrolls inside the frame, so the pane grows with it.
- The detail page (`health_reports/:id`) and the project overview keep their fixed 480px frame (unscoped rule unchanged).
- Related: ADR-041 (editor stacking CSS contract tested at source level).

## Alternatives Considered

- Make the body wrapper a vertical flex container and keep the pane cap: fixes 1280×800 and 1280×1080, but at 1280×600 the frame's minimum height and the pane cap collide, the cap wins and everything below 649px stays hidden (measured).
- Additionally give the pane cap a floor (`max-height: max(calc(100vh - 340px), 36em)`): the floor is a constant, so content is hidden again whenever the fixed parts are larger than expected (an edited report, a flash notice); a larger floor makes the pane run past the viewport even at 1280×800 (bottom at 816px, measured).
- Let the children's minimum height widen the pane (`min-height: min-content` on the pane): Chromium treats block-axis `min-content` / `fit-content` / `max-content` as `auto`, so it had no effect (measured).
- Size the pane with grid `fit-content()`: in the block axis both the min-content and the max-content contribution are the full content height, so a minimum and the natural height cannot be separated.
- Compute the height in JavaScript: CSS alone removes the clipping, so extra layout code is not justified (constitution Principle III).
