# SF-021: Applied a chart-form heuristic to every type without checking what each chart tells the reader

**Date**: 2026-10-17
**Feature**: specs/078-health-report-charts (branch `feature/078-health-report-charts`)
**Artifact**: spec.md (Clarifications, FR-003, FR-005, FR-009); research.md R-004, data-model.md, contracts, plan.md updated as a result
**Category**: intent-misread
**Related**: SF-019, SF-020

## Feedback

After seeing the implementation:

> "I don't understand the point of showing open vs closed — just two items — as a pie chart."
> "Choosing a pie because it shows a proportion is not how you decide. You have to think about which form is effective for this information."

The user also shared a report generated in Claude.ai: number tiles for single figures ("6/7 done, 21%"), stacked horizontal bars for status and workload, a weekly column chart, a one-line interpretation under every chart, and a conclusion headline above everything. No pie chart was used.

## What the AI Wrote

spec.md Clarifications and FR-003 (after SF-020's correction):

> Proportion types (status, tracker, priority, open vs closed, progress distribution) are doughnut charts; assignee, which compares workload per person, is a horizontal bar chart.
> FR-003: ... status (doughnut), tracker (doughnut), priority (doughnut), assignee (bar), open vs closed (doughnut), progress distribution (doughnut)

## Correction

The form is decided per information by what helps the reader read it:

- `status`, `tracker`, `priority`, `assignee`: horizontal bars ordered by count (comparing sizes of several categories; long names stay readable).
- `progress`: one stacked horizontal bar, stages left to right (an ordered composition of three parts).
- `open_closed`: a number tile ("<closed> / <total>" and the rate), not a chart.
- No doughnut. Charts of change (line / column) stay out of scope because the stored metrics are snapshots.
- New: the LLM writes a 1-2 sentence interpretation around each chart (FR-005).

## Root Cause

In SF-020 the user gave a rule of thumb ("a pie for proportions, a line for change, the form has to vary with what it shows"). The AI turned it into a lookup table (anything ratio-like becomes a doughnut) and wrote it into the spec as the user's decision. It never checked the rule against each type's actual data: how many items (two for open/closed), whether the items are ordered, whether the picture says more than the numbers, and how many slices a reader can compare. It also did not look for presentations other than a generic chart (a number tile for a single figure), although the purpose was to make the report easier to read. The heuristic was a starting point for a per-type judgement, not the judgement itself.

## Prevention

When the user gives a general heuristic for a user-visible choice (chart form, layout, grouping), use it only as the default for the first proposal. Before writing it into the spec, go through each item with its real data (count, ordering, what the reader needs to decide) and propose a form per item with the reason, including non-chart presentations, and ask for confirmation. Do not record the heuristic itself as the user's decision in Clarifications.

**Promoted to**: Not yet
