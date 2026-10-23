# CRF-038: Streaming Markdown parser dropped explicit left alignment, breaking RTL parity with the server renderer

**Date**: 2026-10-17
**Source**: GitHub Copilot (PR #525)
**Feature**: branch `bugfix/076-fix-health-report-table-style` / PR #525
**Files**: assets/javascripts/shared/ai_helper_markdown_parser.js, test/javascript/shared/ai_helper_markdown_parser.test.js, docs/adr/057-ai-output-tables-styled-on-the-server.md, wiki/pages/chat-sidebar.md
**Category**: edge-case
**Related**: None (same shared-renderer pattern as SF-015)

## Feedback

Copilot's review overview (https://github.com/haru/redmine_ai_helper/pull/525): the streamed chat parser mishandles explicit left alignment in RTL layouts. PR #525 added `text-align: start !important` for unhinted columns in `#aihelper-chat-conversation`. `md_to_html` emits `align="left"` for a `:---` column, but `AiHelperMarkdownParser` emitted no attribute for it, so under Redmine's `<html dir="rtl">` an explicit left column was right-aligned while streaming and left-aligned after reload. The health report streaming display had the same defect against the `[align=left]` override in `ai_helper_rtl.css`.

## Original Code

```js
if (sep.startsWith(":")) {return "left";}
return "left";
// ...
const alignment = alignments[index] || "left";
const alignAttr = alignment !== "left" ? ` align="${alignment}"` : "";
```

## Fix

Unhinted columns map to `null`; explicit `left`, `center` and `right` all produce an `align` attribute. The parser test now covers `:---` (`align="left"`), `---` (no attribute) and columns beyond the separator row. ADR-057 and the chat wiki page state the parity.

## Root Cause

The AI changed the CSS that interprets the `align` attribute and checked only the server renderer's output (`md_to_html`), because the change was framed as a server-side fix. The same container also holds tables produced by the browser parser, and the CSS comment written in the same PR even says so, but the parser's output for the same Markdown was never compared. The existing parser test pinned the lossy behaviour (`<th>Left</th>`), so nothing flagged it. In LTR the two outputs look identical, so the gap is visible only under RTL.

## Prevention

- When CSS or markup rules key on attributes produced by a renderer, list every renderer that writes into the targeted container (server `md_to_html` and `AiHelperMarkdownParser`) and assert that both produce the same attributes for the same Markdown input, including `:---`, `:---:`, `---:` and `---`.
- When a rule depends on writing direction (`start`/`end`, `[dir=rtl]`), check the result under RTL for each renderer, not only LTR.

**Promoted to**: Not yet
