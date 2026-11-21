---
title: Health Report Charts
type: component
sources: [S051, S052, S053, S054]
updated: 2026-11-21
---

# Health Report Charts

How a one-line chart directive in a health report body becomes a chart on
screen, in the PDF, and in the Markdown export. Part of the
[Project Health Report](./health-report.md).

## Design

- The body carries only `{{ai_helper_chart(<type>, version=<id>|period=<key>)}}`
  on a whole line outside fenced code blocks and CommonMark HTML blocks of
  types 1-5 (`<pre>`, `<!--`, ...); the LLM picks type and position, values
  always come from the metrics stored with the report (S051, S054, ADR-058).
- Ruby (`RedmineAiHelper::HealthReportChart`: `Scanner`, `Directive`, `Resolver`,
  `Chart`/`Item`/`Unavailable`, `Palette`, `SvgRenderer`, `MarkdownArchive`,
  `PromptGuide`) decides everything; the three renderers only draw a `Chart`
  (S051).
- The scanner rules exist twice, in Ruby and in `ai_helper_chart_directive.js`,
  and share one judgment table in `contracts/chart-directive.md` (rows #1-#26);
  the JS copy once tracked only fences, so a directive inside `<pre>` vanished
  while streaming (S051, S052, S054).
- Alternatives rejected: PNG attachments (permissions, old reports, fonts) and
  Mermaid (Node/Chromium for PDF, LLM writes numbers) (S051).

## Forms

The form is chosen per information, not by a proportion-means-pie rule (S053,
ADR-059): `status`/`tracker`/`priority`/`assignee` are count-ordered horizontal
bars, `progress` is one stacked bar of its three stages, and `open_closed` is a
number tile built from ERB HTML (no canvas). There are no doughnuts. The LLM is
asked to write one or two sentences interpreting each chart (S053).

## Behaviour worth remembering

- `chart-<n>.svg` numbers only the drawable charts in order of appearance; an
  unavailable directive becomes a `> ` blockquote and uses no number (S052).
- Comparison reports never draw charts: directives become a message in the
  browser, the PDF and the `.md` export (S051).
- A malformed stored count (`"3"`, `nil`, negative) makes the chart
  `data_missing`, not a 500; `Resolver.new` accepts only a String or nil (S052).
- After generation the browser fetches `health_report_content` for the id sent
  in the `health_report_saved` SSE event; a failed swap shows the error message
  instead of a finished-looking body without charts (S052).
- Starting another generation reuses the same result area, so each generation
  stamps it with `data-ai-helper-generation`; a swap or swap failure of an
  earlier generation that settles late is dropped (S054).
- Charts whose canvases leave the document are `destroy()`ed by the same
  MutationObserver that draws added ones; a canvas removed before the dynamic
  `import("chart.js")` resolves is never drawn (S054).
- Each canvas is followed by a `ul.hidden-for-sighted` (Redmine's class) listing
  the item labels with their counts, outside the chart container, so screen
  readers get the values (S054).

## Gotchas

The chart gotchas are on a separate page. See [Health Report Charts Gotchas](./health-report-charts-gotchas.md) (S051, S052).

## Related

- [Project Health Report](./health-report.md) ·
  [Health Report Markdown Rendering](./health-report-markdown-rendering.md) ·
  [Health Report Generation Completion](./health-report-generation-completion.md)
