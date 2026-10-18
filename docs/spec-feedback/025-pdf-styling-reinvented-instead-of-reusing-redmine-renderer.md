# SF-025: Planned PDF styling tweaks and asked about them instead of reusing Redmine's own PDF renderer as-is

**Date**: 2026-10-18
**Feature**: specs/079-fix-health-report-pdf-table (branch `bugfix/079-fix-health-report-pdf-table`)
**Artifact**: spec.md (FR-006, User Story 5, Edge Cases, Assumptions), research.md (R-001, former R-004)
**Category**: intent-misread
**Related**: SF-024, SF-020

## Feedback

During `/speckit-plan` the user said:

- "Shouldn't you just call Redmine's own processing for turning Markdown into PDF?"
- "Make it the same as when an image is embedded in a Redmine wiki page or issue."
- (After being asked whether to adjust four details to match the browser screen) "What are you talking about? What is the problem with that?"

## What the AI Wrote

The spec's FR-006 table required the PDF to copy the browser screen element by element:

> | 箇条書き | 画面と同じく、入れ子の深さで種類の変わる記号(1段目 ●、2段目 ○、3段目以降 ■)… |
> | インラインコード・コードブロック | 等幅の字体 … |
> | 引用 | 字下げし、左に縦線を付けた斜体(画面の `blockquote` と同じ) |

The plan chose Redmine core's `ITCPDF#RDMwriteFormattedCell`, which draws HTML into a PDF. It then added a research decision (R-004) to rewrite the HTML before drawing: wrap `th` contents in `<b>`, turn inline `code` into `tt`, add `type="square"` to deep `ul`, and rebuild `blockquote` as a table with a grey bar cell. The AI also asked the user three separate questions: how to show images, whether to keep these tweaks, and which of two options to choose.

## Correction

- FR-006 now says the PDF body is the screen's HTML (`md_to_html` plus issue links), drawn by `RDMwriteFormattedCell` with no adjustments. Each element looks the same as in Redmine core's wiki or issue PDF. Images are handled as in core.
- The edge cases and assumptions for alignment, fonts, RTL, list markers and column widths now point to Redmine core's PDF.
- Research R-004, the HTML adjustments, was removed. Calling `RDMwriteHTMLCell` and making the tweaks are now listed as rejected alternatives.

## Root Cause

SF-024 had taught the AI "the export must match the screen", and the AI applied it literally, down to the rendering details. The user meant the content: the same elements, in the same order, with the same text. The AI never checked what an export looks like elsewhere in the product. Redmine core already exports wiki pages and issues to PDF with this same renderer. Those PDFs are the established standard for the medium, and users accept their look. The AI treated each difference between the browser and rbpdf as a defect to fix or a choice to put to the user. It should have seen them as the normal appearance of a Redmine PDF.

The image question had the same cause. Reusing the core renderer already settles how images behave, so there was nothing to ask.

## Prevention

When a feature exports content to a medium that Redmine core already exports to (PDF, CSV, Atom, Markdown), first find the core exporter (`lib/redmine/export/`, `*_pdf_helper.rb`) and reuse it unchanged. Require "same content as the screen, same appearance as Redmine core's export" rather than per-element screen fidelity. Do not plan or ask about styling tweaks to the core renderer's output unless the user asks for a difference from core.

**Promoted to**: Not yet
