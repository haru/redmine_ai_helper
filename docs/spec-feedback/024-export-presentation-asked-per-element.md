# SF-024: Asked about PDF presentation element by element instead of requiring the export to match the screen

**Date**: 2026-10-18
**Feature**: specs/079-fix-health-report-pdf-table (branch `bugfix/079-fix-health-report-pdf-table`)
**Artifact**: spec.md (FR-001, FR-006, FR-008, User Stories 1 and 5, Edge Cases, Success Criteria, Assumptions)
**Category**: intent-misread
**Related**: SF-019, SF-020, SF-021

## Feedback

"Bullet-list rendering and everything else should be the same as the screen. Otherwise the export is pointless. It is wrong to ask about the specification."

The user said this in reply to the fourth clarification question, after already answering one earlier question with "make it the same as the screen".

## What the AI Wrote

The spec decided how the PDF shows each Markdown element one at a time. Where it had no answer, it either asked or picked a PDF-specific behaviour:

> - **太字・斜体・インラインコード・リンク**: 記号を取り除いた文字だけを出す(1.12.0 より前と同じ)。
> - **水平線(`---`)**: 出さない(1.12.0 より前と同じ)。
> - **セルの文字が長い表**: 今と同じく、長い文字は途中で切って `...` を付ける。
> - FR-001: tables split wherever a non-table line appears (the screen's GFM renderer keeps such lines in the table until a blank line).

The AI then asked separate questions about the bullet glyph, numbered lists, header-only tables, and whether a line right after a table belongs to it.

## Correction

FR-006 now states one rule: the PDF body shows what `render_health_report_markdown` shows on screen, in the same order, with the same text and the same kind of formatting. A table maps each screen element to its PDF form. Following that rule:

- FR-001 finds tables with the same rules as the screen.
- FR-008 no longer freezes cell truncation, so cells wrap instead.
- List markers follow the screen's nesting (disc/circle/square).
- Column alignment, code blocks, block quotes, horizontal rules and links are rendered.
- SC-010 compares the element sequence taken from the screen HTML with the one taken from the PDF.

## Root Cause

The AI treated each PDF element as an open presentation choice. SF-019 and SF-020 had taught it to ask about open choices rather than settle them, so it asked. It never asked what an export is for: a copy of the report the user sees on screen. That purpose already answers every per-element question, and the screen renderer (`md_to_html`) is in the same codebase. The AI could have rendered sample Markdown with it and read off the expected result.

The AI also used "same as before 1.12.0" as a reference point, but that older PDF output was itself a lossy simplification, not an agreed design. An answer of "same as the screen" to one question was a sign that the rule applied everywhere. The AI applied it only to that one question.

## Prevention

When a spec covers an export or alternate rendering (PDF, Markdown/zip, email, chat bridge) of content the user already sees on screen, write "matches the screen rendering" as the governing requirement. Name the screen renderer and measure its output for each element and edge case. Ask the user only about what the target medium cannot reproduce, such as interactive controls. Do not ask per element, and do not anchor on the previous export output. When an answer to one clarification states a general rule ("same as X"), apply it to every remaining open point before asking the next question.

**Promoted to**: Not yet
