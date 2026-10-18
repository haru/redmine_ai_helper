# ADR-059: Choose each health report chart's form by what helps the reader

**Date**: 2026-10-17
**Status**: Accepted

## Context

ADR-058 introduced chart directives drawn from stored metrics on screen, in PDF and as SVG. The first implementation drew five of the six chart types as doughnuts because the type "shows a proportion", and only the assignee chart as horizontal bars. Reviewing the result, the user pointed out that a two-item open/closed doughnut adds nothing over the numbers, and that the form must be chosen by what is effective for each piece of information, not by a "proportion means pie" rule. A report generated in Claude.ai (number tiles, stacked bars, an interpretation under every chart) was given as a reference.

## Decision

- The form is a property of each chart type (`ChartType#form`), decided per information (spec.md Clarifications, FR-003, research.md R-004):
  - `status`, `tracker`, `priority`, `assignee`: horizontal bars ordered by count (comparing the size of several categories; long names stay readable).
  - `progress`: one stacked horizontal bar of the three ordered stages.
  - `open_closed`: a number tile ("<closed> of <total> closed (<rate>%)"), not a chart: it is built from ERB HTML and Redmine's existing `.box` and `h2` classes, with no canvas.
- Doughnut and pie forms are not used and not implemented in any of the three renderers.
- The LLM is asked (through `chart_guide`) to write one or two sentences before or after each chart that say what it shows, citing only the figures needed from the metrics. It is not told which form a chart uses.
- Charts of change (line, column) are out of scope: the stored metrics are point-in-time snapshots with no time series.

## Consequences

- Positive: the picture adds information beyond the numbers (ordered comparison, stage composition, a single completion figure); three renderers lose the arc and ring drawing (Chart.js `doughnut`, rbpdf `PieSector`/`Circle`, SVG arcs) and gain a stacked bar and a text tile that are simpler.
- Positive: no new CSS or colors; the tile uses existing Redmine classes.
- Negative: the tile has no Chart.js counterpart, so each renderer handles `:tile` separately (screen: ERB, PDF: text, SVG: text).
- Negative: a time-series chart still needs new data collection and is a separate feature.
- Supersedes only the form choice in the first implementation of ADR-058; the rest of ADR-058 stands.

## Alternatives Considered

Taken from `specs/078-health-report-charts/research.md` R-004:

- All six types as doughnuts: a two-item circle adds nothing over the numbers and the slices of 5-7 items are hard to compare. Rejected.
- All six types as horizontal bars: neither the stage composition of progress nor the completion rate reads at a glance. Rejected.
- Remove `open_closed`: the completion rate is worth showing as a single number; kept as a tile. Rejected.
- Weekly column or line charts: there is no time series in the stored metrics. Rejected for this feature.
