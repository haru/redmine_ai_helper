---
title: Health Report Charts
type: component
sources: [S051, S052]
updated: 2026-10-17
---

# Health Report Charts

How a one-line chart directive in a health report body becomes a chart on
screen, in the PDF, and in the Markdown export. Part of the
[Project Health Report](./health-report.md).

## Design

- The body carries only `{{ai_helper_chart(<type>, version=<id>|period=<key>)}}`
  on a whole line outside fenced code blocks; the LLM picks type and position,
  values always come from the metrics stored with the report (S051, ADR-058).
- Ruby (`RedmineAiHelper::HealthReportChart`: `Scanner`, `Directive`, `Resolver`,
  `Chart`/`Item`/`Unavailable`, `Palette`, `SvgRenderer`, `MarkdownArchive`,
  `PromptGuide`) decides everything; the three renderers only draw a `Chart`
  (S051).
- The scanner rules exist twice, in Ruby and in `ai_helper_chart_directive.js`,
  and share one judgment table in `contracts/chart-directive.md` (rows #1-#20)
  (S051, S052).
- Alternatives rejected: PNG attachments (permissions, old reports, fonts) and
  Mermaid (Node/Chromium for PDF, LLM writes numbers) (S051).

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

## Gotchas

- Redmine 6.0.x has no importmap at all and 6.1.x has one without a `chart.js`
  pin: `ai_helper_chart_heads` must check `respond_to?(:importmap)` and is
  also needed on the project overview partial (S052).
- rbpdf's snake_case methods (`add_page`) are aliases bound to the original
  method, so a `prepend`ed recorder only sees them if it wraps the alias too
  (S052).
- On the project overview a MutationObserver re-adds the POST-based export
  links during generation; the swap must remove them, otherwise charts are
  exported as "no metrics" (S052).
- `renderWithin(node)` on an observer's added node must also test the node
  itself; in Ruby `array[index - 1]` wraps at index 0 (S052).
- The PDF chart code lives in `ProjectHealthPdfChartHelper`, split from
  `ProjectHealthPdfHelper` to stay under RuboCop's module length (S051).

## Related

- [Project Health Report](./health-report.md) ·
  [Health Report Markdown Rendering](./health-report-markdown-rendering.md) ·
  [Health Report Generation Completion](./health-report-generation-completion.md)
