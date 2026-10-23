# SF-019: Allowed raw chart directives to show during streaming without asking

**Date**: 2026-10-17
**Feature**: specs/078-health-report-charts (branch `feature/078-health-report-charts`)
**Artifact**: spec.md
**Category**: unconfirmed-assumption
**Related**: None

## Feedback

During `/speckit-clarify`, the AI asked how the chart directive (the in-body marker that says which chart goes where) should look while a health report is being streamed. The user chose "do not show the chart directive part during generation; the chart appears in its place when generation completes", replacing the behaviour the AI had already written.

## What the AI Wrote

Edge Cases, "生成中の表示" (display during generation):

> ストリーミングで本文を表示している間、チャート指定は文字列として一時的に見えてよい。生成が完了したら、チャートに置き換わる。

(While the body is streamed, the chart directive may be temporarily visible as raw text. It is replaced by the chart when generation completes.)

## Correction

- The edge case now says the chart directive part is not shown during streaming (neither the raw text nor a provisional placeholder), including a partially received directive, and the chart appears in its place when generation completes.
- Added FR-008a: "生成中(本文を少しずつ表示している間)は、チャート指定の部分を表示しない。" (During generation, the chart directive part is not displayed.)
- Recorded the answer in the Clarifications section.

## Root Cause

The AI based the original text on what the current streaming display does by default: the client renders the streamed Markdown as it arrives, so an unrecognised directive would naturally show up as text. It treated that default as acceptable because it was "only temporary", and wrote it as a settled edge case instead of an open question. It should have recognised that the streaming view is the first thing a user sees after clicking "generate", and that showing internal syntax there is a user-facing decision with several reasonable options (show raw text, hide, show a provisional placeholder). It did not ask because it judged the state transient and therefore low impact.

## Prevention

When a spec introduces new markup or syntax that the system later replaces (placeholders, macros, directives), state for every view that renders it — including transient views such as streaming or preview — what the user sees before the replacement happens. If the request does not decide it, ask the user instead of writing "may be visible temporarily".

**Promoted to**: Not yet
