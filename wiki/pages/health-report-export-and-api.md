---
title: Health Report Export, UI & REST API
type: component
sources: [S002, S011, S038, S049, S050, S051]
updated: 2026-11-21
---

# Health Report Export, UI & REST API

PDF/Markdown export, the dashboard UI pieces and the REST endpoint of the [Project Health Report](./health-report.md).

## Export & UI

- **PDF** (individual reports and comparisons) via `ProjectHealthPdfHelper`
  (ITCPDF). The body is drawn from the same HTML as the screen
  (`AiHelperHelper#health_report_html_with_chart_markers`) with Redmine's
  `RDMwriteFormattedCell`, so tables, headings and lists match the screen's
  element kinds and order; charts are drawn at their marker positions. There is
  no fallback rendering: an exception fails the export (feature 079, ADR-061).
  In an RTL language the whole page is switched to right-to-left with
  `pdf.set_rtl`, which also right-aligns the body HTML; `text_align` only
  reaches the header cells, the edit notice and the chart renderer's text
  (feature 079). A body containing `<img>` fails the export, because rbpdf
  would drop such an image without an error (feature 079).
  The **Markdown** download is a **zip archive** holding the Markdown
  file — chart directives replaced with relative links to the bundled chart
  SVGs — plus the SVG images (feature 078, FR-016; S002, S011).
- `AiHelperDashboardController` handles report display, history pagination, PDF
  endpoints, and the Markdown zip export (S011).
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

- [Project Health Report](./health-report.md) — the main page.
