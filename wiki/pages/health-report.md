---
title: Project Health Report
type: component
sources: [S002, S003, S011, S038, S048, S049, S050, S051]
updated: 2026-10-17
---

# Project Health Report

Generates a comprehensive overview of a project's status — metrics such as open
issues, closed issues, and overall health (S002). Reports can be exported to
Markdown and PDF (S002).

> Provenance: detail below is from the DeepWiki doc (S011); `get_metrics` is
> corroborated by the README (S002).

## Generation

`ProjectAgent` (a [worker agent](./multi-agent-architecture.md)) orchestrates
generation with a **dual-pattern** strategy (S011):

- **Version-based**: when the project has open versions, it iterates each,
  pulling metrics via `ProjectTools#get_metrics` (S011).
- **Time-period**: with no open versions, it aggregates metrics over fixed
  windows — "Last 1 Week", "Last 1 Month" (S011).
- **Both** patterns append commit/author activity via
  `ProjectTools#calculate_repository_metrics` (S011).

Data is gathered across issues, versions, and repository activity: `ProjectTools`
(see [Tool System](./tool-system.md)) collects the metrics, `ProjectAgent`
decides what to fetch from project state (S011). Separate YAML prompt templates
in `assets/prompt_templates/project_agent/` guide the version-based vs.
time-period analyses, with localized variants (S011). Generation and comparison
are deeper-reasoning tasks, so they use the optional
[Think Model](./think-model.md) profile when configured (S003).

## Storage & history

Reports are saved automatically to the `AiHelperHealthReport` model — raw
Markdown, the project and triggering user, and structured metrics as JSON (via
`metrics_hash` accessors); scopes handle project filtering and permission-based
visibility, and a `deletable?` check gates deletion (S011). You can review past
reports to track progress (S002).

Stored reports are **editable** by holders of `:edit_ai_helper_health_reports`;
the table also keeps the original body, last editor/time and `lock_version`,
and edited reports are marked everywhere — see
[Health Report Editing](./health-report-editing.md) (S038).

## Comparison

Select two historical reports (radio buttons) to trigger
`health_report_comparison`; `ProjectAgent` runs the analysis and the result is
**streamed over SSE**, with the `AiHelperComparison` JS class applying
incremental UI updates as tokens arrive (S011).

## Export & UI

- **PDF** (individual reports and comparisons) via `ProjectHealthPdfHelper`
  (ITCPDF); **Markdown** raw downloads via the controller (S002, S011).
- `AiHelperDashboardController` handles report display, history pagination, PDF
  endpoints, and Markdown export (S011).
- Saved reports are rendered **server-side** with `md_to_html`, so Markdown
  displays correctly regardless of Redmine's text-formatting setting; before
  feature 064 they went through format-dependent `textilizable` and broke on
  Textile setups — see
  [Health Report Markdown Rendering](./health-report-markdown-rendering.md) ·
  [Health Report Detail Pane Layout](./health-report-detail-pane-layout.md) ·
  [Health Report Generation Completion](./health-report-generation-completion.md)
  (S038). Historically, S011 described client-side parsing by
  `AiHelperMarkdownParser` for this view; that no longer applies to saved
  reports (S011, S038), and feature 076 deleted the last leftover re-parse so
  tables now get Redmine's `table.list` styling on the server (S049,
  [Health Report Markdown Rendering](./health-report-markdown-rendering.md)).
- Export buttons are injected by `ai_helper_project_health.js` (S011). The
  master-detail view (`AiHelperMasterDetail`) originally built detail from row
  data attributes (S011); since 064 it fetches a server-rendered detail pane by
  XHR instead (S038).
- Dashboard generation completion: see
  [Health Report Generation Completion](./health-report-generation-completion.md)
  (S050).
- Saved reports get a record-based Markdown export
  (`.../health_reports/:report_id/markdown`) and an edited notice in PDF; the
  body-POST exports remain only for unsaved streamed reports (S038).

## Charts

Feature 078 lets a report body carry one-line chart directives that are drawn
from the metrics stored with the report, never from numbers written by the LLM
(S051, ADR-058).

- **Syntax**: `{{ai_helper_chart(<type>, version=<version_id>)}}` or
  `{{ai_helper_chart(<type>, period=<period_key>)}}` on a whole line (up to 3
  leading spaces), outside fenced code blocks. Types: `status`, `tracker`,
  `priority`, `assignee`, `open_closed`, `progress`. Period keys: `last_week`,
  `last_month`, `all_time`, `recent` (S051).
- **Forms**: shares of a whole are doughnuts; `assignee` is a horizontal bar
  chart. Colors are Redmine's six issue-report colors; more than 7 items become
  the top 6 plus "others" (S051).
- **Where it is drawn**: Chart.js on screen (ERB emits a `<canvas>` with a data
  attribute), rbpdf shapes in the PDF, a hand-built SVG in the Markdown export.
  All three read the same resolved `Chart` object from
  `RedmineAiHelper::HealthReportChart` (S051).
- **Generation**: the prompt receives a `chart_guide` listing the types and
  targets of the report's metrics. During streaming the directive lines are
  hidden; after the `health_report_saved` SSE event the body is swapped for the
  server-rendered one (S051).
- **Unavailable charts** (unknown type/target, no stored metrics, comparison
  reports) are replaced by a message with the reason (S051).
- **Markdown export is a zip** (`<name>.md` + `charts/chart-<n>.svg`, n counting
  only the drawable charts in order of appearance) for health
  reports; comparison exports stay a single `.md` (S051).
- The edit form has a collapsible help listing the syntax, types and the
  report's targets; the preview needs `report_id` so it can resolve against that
  report's metrics (S051).

## REST API

Generate reports programmatically — e.g. on a cron schedule (S002).

- **Endpoint**: `POST /projects/:project_id/ai_helper/health_report.json` (S002).
- **Auth**: Redmine API key via the `X-Redmine-API-Key` header (S002).
- **Response**: JSON with `id`, `project_id`, `project_identifier`,
  `health_report` (Markdown), `created_at` (S002).
- **Requirements**: the API-key user must have `view_ai_helper` on the project,
  the AI Helper module must be enabled for the project, and REST API must be
  enabled in Redmine admin settings (S002).
- **Chart directives** in `health_report` are returned unchanged; clients that
  render the Markdown themselves must interpret or ignore them (S051).

## Related

- [Multi-Agent Architecture](./multi-agent-architecture.md) ·
  [Tool System](./tool-system.md) · [Think Model](./think-model.md) ·
  [Plugin Overview](./plugin-overview.md) ·
  [Health Report Editing](./health-report-editing.md) ·
  [Health Report Markdown Rendering](./health-report-markdown-rendering.md) ·
  [Health Report Detail Pane Layout](./health-report-detail-pane-layout.md) ·
  [Health Report Generation Completion](./health-report-generation-completion.md)
