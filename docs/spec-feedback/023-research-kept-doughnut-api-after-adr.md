# SF-023: Research R-009 kept the doughnut drawing API after ADR-059 dropped donut charts

**Date**: 2026-10-17
**Feature**: 078-health-report-charts
**Category**: scope-gap
**Related**: SF-020, SF-021, CRF-032

## Feedback

Review comment (comments#13, adopted by the user): `specs/078-health-report-charts/research.md` R-009 still described the PDF rendering with the doughnut API while ADR-059 (accepted the same day) removed doughnut forms from the design.

Original text (R-009 Decision, line 117):

> チャート指定の位置では rbpdf の図形(横棒は `Rect`、ドーナツは `PieSector` と `Circle`。R-004)とテキストでチャートを描く。

and the confirmed-facts line 121:

> rbpdf 1.21.4: `Rect`(public、`rbpdf.rb:9111`)、`PieSector`(public、`:12189`)、`Circle`(public、`:9336`)、...

Fixed text: the Decision now says every chart form (`Rect` + text, no arc/ring API, citing ADR-059), and line 121 lists only `Rect` and notes `PieSector`/`Circle` as public-but-unused since ADR-059 dropped the doughnut.

## Root Cause

When ADR-059 was written, the research sections it cited were updated only where its argument needed them (R-004's chart forms), not the whole feature's research: R-009 described the *implementation approach* (which rbpdf methods to use) and kept the pre-ADR-059 plan. The superseded terms ("doughnut", `PieSector`, `Circle`) were never grepped across the feature's artifacts after the decision changed.

## Prevention

When an ADR changes a design decision, grep the feature's specs directory and docs for every term the decision supersedes (the old form names, the old APIs) and update each occurrence — including sections that describe implementation approach rather than the decision itself — in the same change as the ADR.

**Promoted to**: Not yet
