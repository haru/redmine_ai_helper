# SF-020: Chose one chart form for every chart type for implementation ease without asking

**Date**: 2026-10-17
**Feature**: specs/078-health-report-charts (branch `feature/078-health-report-charts`)
**Artifact**: plan.md, research.md (R-004), data-model.md, contracts/http-and-dom.md; spec.md (Clarifications, FR-003) updated as a result
**Category**: unconfirmed-assumption
**Related**: SF-019

## Feedback

"A pie chart is better for showing proportions, and a line chart is better for showing change. The chart form has to vary depending on what it shows."

## What the AI Wrote

research.md R-004:

> **Decision**: Draw all six types as **horizontal bar charts**. ...
> - There are three renderers (Chart.js, rbpdf, SVG), so a single form is easier to keep consistent.
> **Alternatives**: Draw open/closed and progress distribution as doughnuts → PieSector in rbpdf and SVG arcs would double the three renderers. Rejected (YAGNI).

The plan's Constitution Check also cited "one form (horizontal bar)" as the Simplicity justification.

## Correction

After the user confirmed the choices through clarification questions:

- Doughnut (proportion): `status`, `tracker`, `priority`, `open_closed`, `progress`.
- Horizontal bar (comparing amounts): `assignee`.
- Line chart (change): out of scope this time because the stored metrics have no time series; the chart form is held on each chart type (`ChartType#form`) so a `:line` form can be added with a time-series type.
- spec.md Clarifications and FR-003 now state the form of each type. research.md R-004, data-model.md (`form` on ChartType and Chart), contracts (Chart.js options per form, SVG/PDF doughnut drawing) and plan.md were updated.

## Root Cause

The spec listed the chart types but did not say how each is drawn. The AI filled that gap itself and chose the form that minimised implementation work across the three renderers, then labelled the user-facing alternative as YAGNI. How a chart looks is a user-visible presentation decision, not an internal implementation detail, so simplicity of implementation is not a valid reason to settle it alone. The AI should have asked, in the plan step, which form each type should use (offering "proportion → pie, comparison → bar, change → line" as the usual guidance), instead of treating an unspecified user-visible choice as its own to make. As in SF-019, the AI decided a visible behaviour that the request left open instead of asking.

## Prevention

When a spec leaves a user-visible presentation choice open (chart form, layout, what is shown while loading, wording of a state), do not settle it in plan.md or research.md on implementation-cost grounds. Ask the user, offering the options and the conventional default, and record the answer in spec.md Clarifications. Constitution III (Simplicity/YAGNI) may be cited only for choices the user cannot see.

**Promoted to**: AGENTS.md
