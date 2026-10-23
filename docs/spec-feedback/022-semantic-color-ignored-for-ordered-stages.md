# SF-022: Assigned palette colors by position to stages that carry a meaning

**Date**: 2026-10-17
**Feature**: specs/078-health-report-charts (branch `feature/078-health-report-charts`)
**Artifact**: spec.md (FR-019a); research.md R-006
**Category**: unconfirmed-assumption
**Related**: SF-019, SF-020, SF-021

## Feedback

After seeing the progress distribution on screen:

> "In the progress distribution, completed is yellow. Yellow is normally a warning color. Make it green."

## What the AI Wrote

FR-019a: the six Redmine report colors are assigned to items in display order, repeating from the first from the 7th item on. For the fixed-order progress stages (not started, in progress, completed) this gave red, blue, yellow.

## Correction

FR-019a gains an exception: progress colors are fixed by meaning (not started = red, in progress = blue, completed = green `rgb(76, 175, 80)`). Yellow suggests a warning, and the palette's green is closer to teal.

## Root Cause

The color rule was copied from Redmine's issue report chart, whose categories (statuses, trackers) have no inherent meaning. The AI applied it to progress stages without checking whether any item carries a meaning that a color already signals (done = green, warning = yellow). The same mechanical application as SF-021, here for color instead of form.

## Prevention

When a spec assigns colors from a generic palette, list the items whose names imply a status (done, failed, warning, overdue) and fix their colors by meaning; apply positional assignment only to meaningless categories.

## Promoted to

Not yet
