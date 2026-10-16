# SF-016: Required table alignment to stay "as before" without measuring it in each view

**Date**: 2026-10-16
**Feature**: specs/076-fix-health-report-table-style (branch `bugfix/076-fix-health-report-table-style`)
**Artifact**: spec.md (FR-004, FR-006, Edge Cases, User Story 4; added SC-005)
**Category**: unconfirmed-assumption
**Related**: SF-013, SF-015

## Feedback

During `/speckit-plan`, the AI measured the column alignment of the tables in every view and asked the user how to handle the results. The user chose to align columns as the Markdown says in every view, including the chat streaming display, and agreed to rewrite FR-006.

## What the AI Wrote

- FR-006: "Column alignment (left, center, right) must be displayed the same as before the fix."
- Edge case: "Tables with alignment markers (`:---:` etc.): left, center and right alignment display the same as before the fix."
- FR-004 froze "the streaming display during report generation" without saying it meant health reports only.

## Correction

- FR-006 now requires every view (the five health report views, chat history, issue summary, wiki summary and the chat streaming display) to follow the Markdown alignment markers. Columns without a marker align to the start of the writing direction (left in LTR). The health report RTL display keeps its existing RTL rules.
- Added SC-005: a table with no-marker, left, center and right columns shows left, left, center, right in every view (1280px, LTR).
- The alignment edge case now says the health report tab, detail page and preview change (from all-left to the markers), matching the project overview.
- FR-004 now freezes only the health report streaming display. User Story 4 got an alignment acceptance scenario.

## Root Cause

The AI assumed alignment was correct and consistent today, so "same as before" looked like a safe no-regression rule. It had not measured it. Plan-time measurement showed four different behaviours:

- Health report tab, detail page and preview: markers ignored, every cell left, because `.ai-helper-final-content * { text-align: left }` overrides the `align` attribute.
- Project overview (JavaScript re-render, `table.list`): markers honoured, other columns left.
- Chat history and summaries: browser default (headers centered, cells at the start) plus markers.
- Chat streaming (`table.list` from the JavaScript parser): every cell centered, because Redmine's `table.list td { text-align: center }` overrides the `align` attribute.

So "as before" had no single meaning, and the fix itself (adding `list`) would center every chat and summary cell. The AI should have measured the computed `text-align` in each view, with and without the planned class, before writing a "must not change" rule.

## Prevention

Before a spec says a visual property must stay "the same as before", measure that property (computed style) in every view the change touches, both now and with the planned change applied. If the views differ today or the change alters one, state the target behaviour explicitly and ask the user, instead of writing "same as before".

**Promoted to**: Not yet
