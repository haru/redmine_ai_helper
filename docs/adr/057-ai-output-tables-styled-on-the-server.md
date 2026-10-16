# ADR-057: Style AI output tables on the server, not by re-parsing in the browser

**Date**: 2026-10-16
**Status**: Accepted

## Context

AI output is rendered as Markdown on the server by `AiHelperHelper#md_to_html`, which is used by every server-side display surface: the health report views (`render_health_report_markdown`), the chat history and the issue/wiki summaries. The `<table>` elements it produced carried no class, so Redmine's standard `table.list` styling (grey header row, borders, striped rows) never applied to them. Users reported that a stored health report showed coloured tables in the project overview but unstyled tables in the dashboard tab and the report detail page (feature 076).

The overview looked different for a leftover reason: after page load, browser JavaScript re-parsed the raw Markdown stored in a hidden field and replaced the server-rendered body with `parser.parse(...)` output, whose tables do carry `class="list"`. Two such re-parses existed in `assets/javascripts/project_health/ai_helper_project_health.js`. Feature 064 had already rejected client-side rendering for display because the HTML must come from ERB and a browser-side parser skips the server-side sanitization (`specs/064-health-report-edit/research.md`, "JS の `AiHelperMarkdownParser` でクライアント描画"); ADR-044 records the related decision to render stored reports as Markdown. The re-parse code had survived feature 064.

Measurements and details: `specs/076-fix-health-report-table-style/research.md` (R-001 to R-004). ADR-044 is not changed (append-only); this ADR complements it.

## Decision

- `md_to_html` sets `class="list"` on every `<table>` of the parsed fragment, in both Redmine version branches. The class is set **after** sanitization and scrubbing (Redmine's sanitizer allowlist does not include `class` on tables, and setting it afterwards means a class written in the Markdown body cannot leak into the output) and **before** `fragment.to_s`. The 6.x branch verifies `MarkdownPipeline.call(text)[:output]` is a `Nokogiri::XML::DocumentFragment` and raises otherwise (no fallback). The fragment is never serialized and re-parsed.
- Both browser-side re-parses of stored health reports are removed. The second `DOMContentLoaded` handler is deleted entirely: besides the re-parse it only wired export links whose element IDs (`ai-helper-markdown-export-detail`, `export-markdown-link`, `markdown-export-form`) are output nowhere in `app/` or `assets/` (grep-verified), so the whole handler was dead apart from the re-parse. The hidden field and `handlePdfExport`/`handleMarkdownExport` stay untouched; exports keep working.
- The table CSS rules of `ai_helper.css` extend to the chat (`#aihelper-chat-conversation`) and summary (`.ai-helper-summary-body`) containers. Columns without an explicit Markdown alignment align to `text-align: start !important` in those containers (RTL-safe); the health report containers keep their `left` rules and RTL overrides. No colours, fonts or borders are added — the visual style comes from Redmine's `table.list` rules.

## Consequences

- Every server-rendered AI output table gets Redmine's standard table styling, identically in all the health report displays (the overview, the dashboard tab, the report detail page, the original report and the edit preview; R-002), the chat history, the issue/wiki summaries and the chat streaming display.
- Column alignment follows the Markdown alignment hints everywhere; unspecified columns align left in LTR. The health report tab/detail/preview previously ignored the hints and forced everything left — that changes by design (approved during clarify, recorded in SF-016/SF-017).
- Row striping follows Redmine's own rules: tables inside `.box` (health report) show no stripes, the chat and summary containers stripe even rows (`application.css`). View-dependent stripe differences are Redmine core behaviour and are not papered over by plugin CSS.
- Non-table HTML is byte-identical to before: setting the attribute on the fragment avoids a measured drift from re-parsing (task-list `<li>` and the code-block `div.pre-wrapper` gained newlines, and `disabled=""` degraded to `disabled`).
- The Markdown parser class `AiHelperMarkdownParser` remains in use for streaming displays; only the stored-report re-parse path is gone.

## Alternatives Considered

- Add the `list` class only in `render_health_report_markdown`: only the health report would be fixed, but clarify decided that the chat history and the issue/wiki summaries must match too (FR-005); all of them share `md_to_html`.
- Replicate Redmine's table colours with plugin CSS (e.g. `.ai-helper-final-content table`): writes plugin-specific colours, against the AGENTS.md rule to use Redmine's existing classes, and would not follow Redmine theme changes.
- Add a Loofah scrubber to the scrubber chain: only affects the Redmine 7.x branch; the 6.x `MarkdownPipeline` branch would still need separate handling.
- Serialize the fragment and re-parse it to set the class: measured to change non-table HTML (see Consequences), violating "table styling must not change anything else" (FR-005).
- Keep a plugin-specific class (e.g. `ai-helper-markdown-table`) instead of `list`, or add a shared container class to the three ERB templates plus the JS-generated one: both touch more code than extending the CSS selectors, for the same result.
- Delete only the re-parse part of the second `DOMContentLoaded` handler and keep its export wiring: the wired IDs are not output anywhere, so the kept code would be dead.
