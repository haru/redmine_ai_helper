# SF-014: Required an exact "shrink to the remaining height" layout without checking that CSS can express it

**Date**: 2026-10-15
**Feature**: specs/075-fix-health-report-clipping (branch `bugfix/075-fix-health-report-clipping`)
**Artifact**: spec.md (FR-006)
**Category**: unconfirmed-assumption
**Related**: SF-013

## Feedback

During `/speckit-plan`, the AI found that the exact FR-006 behaviour could not be built in CSS together with FR-007. It proposed to cap the report frame by the viewport height minus a typical height for the parts around it (14em). If those parts grow (for example, a flash notice right after saving), the pane extends past the bottom of the viewport by that amount, but nothing is hidden. The user answered: "That is fine."

## What the AI Wrote

FR-006: "The report frame must shrink until it fits the height left in the detail pane, but not below a minimum of about 10 lines. In no case may the frame push the meta information or the links out of the detail pane."

## Correction

FR-006 now says the frame shrinks to the viewport height minus the *typical* height of the parts outside the frame, with the 10-line minimum. When those parts are taller than typical, the detail pane may extend past the bottom of the viewport by the difference, and page scrolling reaches it (as in FR-007). The "never push out of the pane" rule is unchanged. A plan-time clarification records the decision.

## Root Cause

The AI wrote FR-006 and FR-007 as a pure description of the desired result. It did not check whether the planned approach could produce both. The clarification answer ("keep the in-frame scroll, but let the pane grow below the viewport on short screens") was written as an exact rule: the pane is capped by the viewport, but its children's minimum heights may override the cap. CSS cannot express that rule. A `max-height` always wins over the children's minimum sizes. Chromium treats `min-height: min-content` like `auto` in the block axis. The plan-time experiments on a real browser showed this. The spec was written before any feasibility check, and nothing marked the rule as depending on one.

## Prevention

When a UI requirement combines a size limit with an exception driven by content (for example, "fit the viewport, but grow when the content's minimum does not fit"), check in the same step that the target technology can express it. Look at the existing CSS and try the rule on a real browser if needed. If it cannot be expressed, write the requirement with the approximation it allows (for example, an estimated height for the fixed parts) or ask the user before finalizing the spec.

**Promoted to**: Not yet
