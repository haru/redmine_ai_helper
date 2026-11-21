---
title: Health Report Editor Toolbar & Preview
type: decision
sources: [S038]
updated: 2026-11-21
---

# Health Report Editor Toolbar & Preview

The edit form's toolbar and preview. Split from [Health Report Markdown Rendering](./health-report-markdown-rendering.md).

## Editor toolbar

- **Gotcha**: `wikitoolbar_for` delegates to the configured formatter, giving a
  Textile toolbar on Textile setups; `extend`ing
  `Redmine::WikiFormatting::CommonMark::Helper` into the view would override
  every other formatter helper in that view (S038).
- So helper `ai_helper_markdown_toolbar_heads` emits the same assets as
  CommonMark's `heads_for_wiki_formatter` (`jstoolbar/jstoolbar`,
  `jstoolbar/common_mark`, the language file, `wikiImageMimeTypes` /
  `userHlLanguages`, the jstoolbar CSS) into `content_for :header_tags`, only
  on pages shown to users who can edit (S038).
- The detail pane arrives via XHR, so inline `<script>` initializers would not
  run; JS builds the toolbar once on "Edit" (`new jsToolBar` → `setHelpLink`
  → `setPreviewUrl` → `draw()`), reading URLs from textarea `data-*`
  attributes (S038).

## Preview

`POST /projects/:id/ai_helper/health_reports/preview` renders `text` with
`render_health_report_markdown`. Redmine's own delegated handler in
`application-legacy.js` (`div.jstTabs a.tab-preview`, posting `.wiki-edit`
into `.wiki-preview`) does the request, so no extra JS is needed. The standard
`preview_text_path` was rejected because it uses `textilizable` (S038).

## Related

- [Health Report Markdown Rendering](./health-report-markdown-rendering.md) — the main page.
