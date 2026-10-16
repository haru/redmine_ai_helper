# SF-015: Limited a fix in a shared Markdown renderer to one screen and froze the other callers

**Date**: 2026-10-16
**Feature**: specs/076-fix-health-report-table-style (branch `bugfix/076-fix-health-report-table-style`)
**Artifact**: spec.md (FR-001, FR-005, SC-004)
**Category**: scope-gap
**Related**: SF-003, SF-007

## Feedback

During `/speckit-clarify`, the AI asked whether the server-side table style fix should cover only health reports or every AI output that the server renders from Markdown. The AI had found that chat history, issue summaries and wiki summaries use the same renderer and have the same defect. The user chose "all of them" (health reports, chat history, issue summaries, wiki summaries).

## What the AI Wrote

- FR-001 required the standard table style only for the health report views.
- FR-005: "The FR-001 change must not affect other views that use the same Markdown conversion: chat answers, issue summaries and wiki summaries."
- SC-004: "When chat answers, issue summaries or wiki summaries contain a table, their appearance does not change from before the fix."

## Correction

- FR-005 now requires the standard table style for chat history, issue summaries and wiki summaries too, and keeps every non-table element unchanged.
- SC-004 now checks that those tables get the same header and even-row colours as the health report tables.
- Added User Story 4 (chat history and summary tables look the same as during streaming).
- The spec title now covers AI output in general.

## Root Cause

The defect was reported on health reports, and the AI scoped the spec to the reported screen. The cause it had found was in the shared server-side renderer (`md_to_html`), which it knew from the code was also used by the chat and summary views. It then wrote the other callers as "must not change" to keep the fix small, instead of checking whether they had the same defect. The streaming chat display uses the JavaScript parser, which adds the table class, and the stored chat history uses `md_to_html`, which does not. So the other callers had exactly the same inconsistency. The AI did not ask the user whether they should be fixed too. It caught this only in clarify.

## Prevention

When the cause of a bug is in a shared code path, list every caller of that path (grep it) in the same step. For each caller, check whether it shows the same defect. Do not write a caller as "must not change" unless you have confirmed that it is unaffected. If other callers are affected, include them in the spec or ask the user about the scope before you finalize it.

**Promoted to**: AGENTS.md
