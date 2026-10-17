---
title: Health Report Markdown Rendering
type: decision
sources: [S038, S049]
updated: 2026-10-16
---

# Health Report Markdown Rendering

Stored [Project Health Reports](./health-report.md) are always rendered and
edited as **Markdown, independent of Redmine's text-formatting setting**
(Textile / Markdown / none). Decided in feature 064 alongside
[Health Report Editing](./health-report-editing.md); ADR-044 records it (S038).

## Display: `md_to_html`, not `textilizable`

- Before 064, saved reports were shown with `textilizable`, which follows
  `Setting.text_formatting` — so Markdown bodies rendered wrongly on
  Textile-configured Redmines (S038).
- Now a helper `render_health_report_markdown(text)` =
  `linkify_issue_references(md_to_html(...))` is used in all three places: the
  AI Helper tab detail pane, the standalone report page, and the project
  overview (S038).
- `AiHelperHelper#md_to_html` is the format-independent CommonMark pipeline
  already used by chat, issue summary and wiki summary; it runs Redmine's
  sanitizer/scrubber and absorbs Redmine 6.x/7.x differences. `#123`
  references still become links (S038).
- Rejected: calling `Redmine::WikiFormatting.to_html("common_mark", ...)`
  directly (duplicates `md_to_html`); client-side `AiHelperMarkdownParser`
  (HTML must come from ERB, and it skips server-side sanitizing) (S038).

## Tables & the removed client-side re-parse

- `md_to_html` sets `class="list"` on every `<table>` of the parsed fragment
  **after** sanitization (Redmine's sanitizer allowlist has no table `class`,
  so a class written in the body cannot leak) and **before** `to_s`. Re-parsing
  the serialized HTML was measured to drift non-table markup (newlines in
  task-list `<li>` and the code-block `div.pre-wrapper`, `disabled=""` becoming
  `disabled`), so the fragment attribute is set in place (S049, ADR-057).
- The Redmine 6.x branch raises unless `MarkdownPipeline.call(text)[:output]`
  is a `Nokogiri::XML::DocumentFragment` — no fallback (S049).
- Feature 076 removed the leftover browser-side re-parse of saved reports
  (hidden-field Markdown re-parsed into `#ai-helper-project-health-result` on
  load), the last surviving client-side rendering path; the hidden field and
  the PDF/Markdown export handlers stay (S049). Feature 064's rejection of
  client-side rendering is thereby enforced for saved reports (ADR-057); the
  freshly streamed report is still rendered by `AiHelperMarkdownParser`.
- The table CSS of `ai_helper.css` extends to the chat and summary containers;
  columns without an explicit Markdown alignment use `text-align: start`
  there (RTL-safe), while the health report containers keep `left` and their
  RTL overrides (S049).

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

## Server-rendered detail pane

Selecting a history row now fetches the detail pane with an XHR
`GET .../health_reports/:report_id` instead of assembling it in JS
(`buildDetailHTML`). The row's `data-report-content`-style attributes,
`buildDetailHTML` and `exportMarkdown` are removed. Reason: edit buttons,
edited/original views and the edit form depend on permissions, and building
them in JS would leak permission logic to the client and keep two HTML paths
(initial server render vs. JS render). Full-page reload on row select was
rejected as a UX regression (S038).

## Related

[Project Health Report](./health-report.md) ·
[Health Report Editing](./health-report-editing.md) ·
[AI Chat Sidebar](./chat-sidebar.md)
