# ADR-058: Draw health report charts from stored metrics via placeholder directives

**Date**: 2026-10-17
**Status**: Accepted

## Context

Health reports are Markdown written by an LLM. Users want charts (issues by status, by assignee, and so on) inside the report on screen, in the PDF export and in the Markdown export. An LLM cannot output images, and asking it to write the numbers risks values that do not match the project's metrics. The report record already stores the metrics JSON it was generated from (`ai_helper_health_reports.metrics`). Attaching generated images to the report (the existing attachment mechanism) was considered and not used (see Alternatives).

## Decision

- The report body carries only a one-line chart directive, for example `{{ai_helper_chart(status, version=12)}}`. The LLM chooses the chart type and position; the values always come from the stored metrics. Users can add or remove directives when editing the report.
- Charts are drawn every time the report is displayed or exported, from the stored metrics, by `RedmineAiHelper::HealthReportChart` (directive scanner, resolver, value objects). The scanner rules (one line, outside fenced code blocks and CommonMark HTML blocks of types 1-5) are implemented identically in Ruby and JavaScript and share one test table.
- There are three renderers fed by the same `Chart` object: Chart.js on screen (ERB emits a `<canvas>` with a data attribute), rbpdf shapes in the PDF, and a hand-built SVG string in the Markdown export. No image library or server font is required.
- The Markdown export of a health report is always a zip: `<name>.md` plus `charts/chart-<n>.svg`, where n numbers the drawable charts in order of appearance. A directive that cannot be drawn is replaced with a one-line blockquote that states the reason. Comparison reports never draw charts (directives are replaced with an explanatory message) and keep exporting a single `.md` file.
- Chat and summary rendering are unchanged; only health report bodies resolve directives.

## Consequences

- Positive: no attachment storage, permissions or capacity management; values cannot be wrong because the LLM never writes them; older reports with stored metrics can gain charts by adding a directive; the PDF change is a branch in the existing flow (R-009, R-016).
- Positive: the three renderers share colors, ordering and the "others" grouping through the resolver (FR-019).
- Negative: three drawing implementations (Chart.js, rbpdf, SVG) must be kept visually consistent (R-016).
- Negative: the directive syntax is project-specific and documented in the README, and chart types are limited to the predefined set.
- Negative: Markdown export changes from `.md` to `.zip`; this must be announced in the release notes.

## Alternatives Considered

Taken from `specs/078-health-report-charts/research.md`:

- Save chart PNGs as attachments and reference them with `![](chart.png)` (R-016, option A): needs attachment permissions, deletion and capacity management, past reports have no charts and need regeneration, the PDF flow would have to be rebuilt, and servers without ImageMagick and Japanese fonts cannot produce readable labels. Rejected.
- Mermaid (R-016, option C): the PDF would need Node.js and Chromium on the server, and the LLM would still write the numbers. Rejected.
- Find the directive in the converted HTML paragraphs instead of in the Markdown lines (R-002): a directive without a preceding blank line is merged into the previous paragraph and is missed. Rejected.
- HTML comments as directives (R-002): the sanitizer removes them and they are hard to see when editing. Rejected.
- A Stimulus controller instead of a classic script (R-007): Stimulus registration is awkward for plugins across Redmine 6.x and 7.x. Rejected.
- Load `chart.min` on every page (R-007): adds about 200 KB to every page on Redmine 6.x. Rejected.
- Look up the latest report on the client through `project_health_metadata` after generation (R-008, alternative a): points at the previous report when the new one was not saved. Rejected.
