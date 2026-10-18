# CRF-064: Images silently dropped from the PDF and a marker raise without diagnostic

**Date**: 2026-10-18
**Source**: Local AI review (speckit-review-run, `specs/079-fix-health-report-pdf-table/review-results.md`)
**Feature**: branch `bugfix/079-fix-health-report-pdf-table`
**Files**: lib/redmine_ai_helper/export/pdf/project_health_pdf_chart_helper.rb, app/helpers/ai_helper_dashboard_helper.rb
**Category**: error-handling
**Related**: CRF-003, CRF-014, CRF-022

## Feedback

The review's errors/types findings: (a) `RDMwriteFormattedCell(..., html, [])` passes an empty attachment list, so Redmine's `ITCPDF#get_image_filename` returns nil for any `<img src>`, rbpdf's `proc_image_file` rescues its own error and draws nothing — an image in the body disappears from the PDF without any signal, while the screen shows it; (b) both renderers raised the bare string "Chart marker paragraph was not rendered in the report body", which names neither the failing directive nor how many markers remain, although the two raise sites are in different classes.

## Original Code

```ruby
pdf.RDMwriteFormattedCell(0, 5, "", "", html, [])
```

```ruby
raise "Chart marker paragraph was not rendered in the report body" unless markers.empty?
```

## Fix

`render_pdf_body` now raises when the converted fragment contains `<img>` elements ("the report body contains N <img> element(s), but images cannot be drawn in the PDF"), with the rbpdf behaviour documented in the method comment and the wiki. Both raise sites append the remaining marker count, the directive's `source` and the marker text; the screen side counts what is left from the failing index. Tests drive both.

## Root Cause

The AI treated the PDF writer as a black box that "takes HTML" and never traced what it does with each input shape — one look at `get_image_filename` (`lib/redmine/export/pdf.rb`) and `proc_image_file` (rbpdf) shows the silent skip. The raise message was written from the raising code's point of view instead of the maintainer's, who needs to know which directive was lost — the same trap CRF-014/CRF-022 already recorded for log lines.

## Prevention

Before handing data to a third-party renderer, read the library source for what it does with every input shape you pass; any input it silently ignores must be rejected at the boundary with a raise (never a log-and-continue). Every raise that reports a lost or unmatched item names the item's source and how many remain.

**Promoted to**: Not yet
