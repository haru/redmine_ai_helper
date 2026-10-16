# CRF-032: ADR and CSS comments described a cause and alternatives that research did not record

**Date**: 2026-10-15
**Source**: Local AI review (`/speckit-review-run`, code and comments agents)
**Feature**: branch `bugfix/075-fix-health-report-clipping`
**Files**: docs/adr/056-dashboard-health-report-frame-capped-by-viewport.md, assets/stylesheets/ai_helper.css
**Category**: doc-comment
**Related**: CRF-023, CRF-025, CRF-028

## Feedback

- ADR-056 Context blamed the frame's `min-height: 360px`. research.md R-001 records a different cause: `.ai-helper-health-report-body` is not a flex container, so the frame's `max-height: 100%` resolved to the full wrapper height without subtracting the meta and edit-link siblings (frame 458px at 1280×800, above 360px). tasks.md T017 asked for R-001's cause.
- ADR-056 Alternatives listed options research never evaluated (pane `overflow-y: auto`, `position: sticky`), attached the Chromium `min-content` finding to the wrong option, gave the JavaScript option an unsupported reason ("flickers on load"), and omitted three options R-002 measured and rejected.
- CSS comment: the 14em breakdown said "margins" where R-002 measures pane padding and border; the narrow-width comment "keep the pre-fix values" described a transitional state and did not say why `align-self: auto` is needed; the reason for `flex-start` was missing.

## Original Code

```markdown
The report frame had `min-height: 360px`, which exceeds the room left in the pane on common screens.
- Compute the height in JavaScript on resize: ... and flickers on load.
```

## Fix

Rewrote the ADR Context from R-001 (DOM structure, measurements, the role of `min-height` only at 1280×600) and replaced Alternatives with R-002's five options and their recorded reasons. Corrected the CSS comments (padding and border; why `flex-start` and `align-self: auto`).

## Root Cause

The AI wrote the ADR from its memory of the investigation rather than from research.md, which had been written earlier in Japanese. It summarised the most visible number (`min-height: 360px`) as the cause and filled Alternatives with plausible generic options instead of copying the recorded ones. T017 named R-001 as the source, but the AI did not reopen it.

## Prevention

- When an ADR or comment summarises a research.md decision, open the cited R-NNN section in the same step and take the cause, numbers and alternatives from it; every alternative in the ADR must appear in research with the same rejection reason.
- Code comments describe the final state and the reason for each value, never "pre-fix" or "kept as before".

**Promoted to**: AGENTS.md
