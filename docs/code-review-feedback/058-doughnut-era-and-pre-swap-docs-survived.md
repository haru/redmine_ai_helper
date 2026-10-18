# CRF-058: Doughnut-era and pre-swap docs survived in specs, wiki and comments

**Date**: 2026-10-17
**Source**: Local AI review (speckit-review-run, 6 parallel agents)
**Feature**: branch `feature/078-health-report-charts` (fix not yet committed)
**Files**: assets/javascripts/project_health/ai_helper_health_report_chart.js, lib/redmine_ai_helper/health_report_chart/chart.rb, palette.rb, lib/redmine_ai_helper/health_report_chart/prompt_guide.rb, specs/078-health-report-charts/research.md, wiki/pages/health-report.md, wiki/pages/health-report-markdown-rendering.md, wiki/pages/health-report-generation-completion.md, wiki/INDEX.md
**Category**: doc-comment
**Related**: CRF-007, CRF-011, CRF-032, CRF-037, CRF-052

## Feedback

- The chart loader's JSDoc said `@throws ... not doughnut or bar` while the code accepts bar/stacked and throws for doughnut (ADR-059 reversed the forms).
- "One slice/bar of a chart" (`chart.rb`) and "fill slices and bars" (`palette.rb`) kept the doughnut-era "slice" wording.
- `research.md` R-009 still described the PDF donut via rbpdf `PieSector`/`Circle`; ADR-059 and the implementation use `Rect` only.
- The chart loader's header comment said charts appear as their directives arrive during streaming; during streaming directives are stripped — charts exist only after the swap to the saved, server-rendered body.
- `prompt_guide.rb`'s module doc did not mention the interpretation-sentence instruction added in 49cc508b, and the guide body's "do not copy numbers into text" read against "mention only the needed figures".
- Out-of-diff wiki pages described the pre-078 world: Markdown export as a raw `.md` (it is now a zip with chart SVGs), streaming display surviving completion (completion now swaps in the server-rendered body), export links arriving only on pane reload (`addReportExportLinks` builds them after the swap); `wiki/INDEX.md` lacked ADR-059.

## Fix

JSDoc and the two "slice" comments were rewritten to the bar/stacked/tile forms; R-009 now names `Rect` only and notes `PieSector`/`Circle` as unused per ADR-059; the loader comment states the post-swap timing; the module doc summarises the interpretation-sentence instruction and the guide's two sentences no longer read as contradictory; the three wiki pages describe the zip export, the completion swap and the post-swap export links, and the INDEX entry cites ADR-059.

## Root Cause

The comments and specs were written before ADR-059 changed the chart forms and before the swap feature redefined completion; the CRF-052 fix pass updated comments inside the diff but nothing re-checked out-of-diff documents (wiki, research) and wording that predated the design change.

## Prevention

When a decision record changes a design (forms, timing, output format), grep specs, wiki and JSDoc for the superseded terms in the same change ("doughnut", "slice", `PieSector`, "raw Markdown"), and treat out-of-diff docs reachable from the feature (wiki pages, research sections cited by ADRs) as part of the change's definition of done (CRF-007).

**Promoted to**: Not yet
