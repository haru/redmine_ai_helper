# SF-032: Offered popup default placements unrelated to the sidebar the form comes from

**Date**: 2026-11-01
**Feature**: specs/083-chat-form-popup (branch `feature/083-chat-form-popup`)
**Artifact**: spec.md
**Category**: unconfirmed-assumption
**Related**: SF-019, SF-020

## Feedback

"I want it to look as if the sidebar form simply popped out. Show it at the same size, almost overlapping the sidebar, and moved just slightly to the lower left."

## What the AI Wrote

An assumption in spec.md: "The popup's default position and size: wider than the sidebar, shown on the right side of the screen." The clarification question then offered only bottom-right at about 480x640px, right edge at full height, and centered at about 720x640px.

## Correction

FR-014 now states that the default size equals the sidebar chat form and the default position almost overlaps that form, offset slightly to the lower left. The assumption was removed.

## Root Cause

The AI based the default and the options on common chat-widget layouts and on the request's complaint that the sidebar is narrow, reading the popup's first display as a chance to fix the width at once. It did not consider the transition from the sidebar as part of the experience, so no option kept continuity with where the form was. It also recorded the default as an assumption before asking, although the choice is visible to the user.

## Prevention

When a spec moves an existing UI element into a new container, offer an initial size and position derived from the element's current size and position as one of the options, and do not record a visible default as an assumption before the user has chosen it.

**Promoted to**: Not yet
