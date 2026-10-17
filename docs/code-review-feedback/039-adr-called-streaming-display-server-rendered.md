# CRF-039: ADR listed the browser-rendered streaming display among server-rendered tables

**Date**: 2026-10-17
**Source**: GitHub Copilot (PR #525)
**Feature**: branch `bugfix/076-fix-health-report-table-style` / PR #525
**Files**: docs/adr/057-ai-output-tables-styled-on-the-server.md
**Category**: doc-comment
**Related**: CRF-011, CRF-032, CRF-037

## Feedback

Copilot's review overview (https://github.com/haru/redmine_ai_helper/pull/525): the ADR needs corrected rendering-boundary wording. ADR-057's Consequences said "Every server-rendered AI output table gets Redmine's standard table styling ... and the chat streaming display", but the streaming display is rendered in the browser by `AiHelperMarkdownParser`, not by `md_to_html`.

## Original Code

```markdown
- Every server-rendered AI output table gets Redmine's standard table styling, identically in all the health report displays (...), the chat history, the issue/wiki summaries and the chat streaming display.
```

## Fix

The sentence now lists only the server-rendered surfaces, and a following sentence says the streaming display is styled because it sits inside `#aihelper-chat-conversation` and the parser already emits `table.list`, not because of the `md_to_html` change.

## Root Cause

The AI built the list of affected displays from the CSS selectors it extended (which do cover the streaming container) and then attached it to a sentence about the server-side change. It did not check which renderer produces each listed display, so the claim's scope was wider than the code path it described.

## Prevention

- When an ADR or doc sentence attributes an effect to a specific code path ("server-rendered", "via `md_to_html`"), every item listed in it must be produced by that code path; items reached by another path go in a separate sentence that names that path.

**Promoted to**: Not yet
