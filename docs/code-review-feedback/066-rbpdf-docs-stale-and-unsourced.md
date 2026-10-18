# CRF-066: Chart helper comment and rbpdf claims described the earlier design or nothing checkable

**Date**: 2026-10-18
**Source**: Local AI review (speckit-review-run, `specs/079-fix-health-report-pdf-table/review-results.md`)
**Feature**: branch `bugfix/079-fix-health-report-pdf-table`
**Files**: lib/redmine_ai_helper/export/pdf/project_health_pdf_chart_helper.rb, lib/redmine_ai_helper/export/pdf/project_health_pdf_helper.rb, wiki/pages/health-report-charts.md, wiki/pages/health-report.md
**Category**: doc-comment
**Related**: CRF-007, CRF-011, CRF-052, CRF-058

## Feedback

The review's comments findings 8 and 9 plus the comments suggestions: (a) the module comment still said "Splits a health report body at its chart directives and draws the resolved charts", while the module now converts and draws the whole body HTML; (b) ADR-061's Consequences made rbpdf look-and-feel claims (image file name printed, quotes indented, bullets repeat after three levels, inline code not monospaced) with no source, and the "prints the file name" claim does not match rbpdf's code, which draws nothing; (c) neither the ADR nor the wiki recorded that RTL body alignment now depends on `pdf.set_rtl` with `text_align` reaching only the header, notice and chart text.

## Original Code

```ruby
# Splits a health report body at its chart directives and draws the
# resolved charts into a PDF with rbpdf shapes and text: ...
module ProjectHealthPdfChartHelper
```

```markdown
- Images are not fetched: with no attachments, rbpdf prints the file name instead
  of the image, and no external URL is requested.
```

## Fix

The module comment now describes converting and drawing the whole body; `write_pdf_html`'s comment explains the empty-string "current position" arguments; `project_health_to_pdf`'s YARD states the RTL/`text_align` split. The wiki (`health-report-charts.md`) records the module's body-drawing scope, the rbpdf claims with their code locations (`openHTMLTagHandler`/`closeHTMLTagHandler`, the missing `code` case, `putHtmlListBullet`'s `deftypes[(listdepth - 1) % 3]`, `get_image_filename` returning nil and `proc_image_file` rescuing), and `health-report.md` documents the RTL behaviour and the `<img>` raise. The append-only ADR was left untouched; the wiki carries the corrections.

## Root Cause

The comments were written for the pre-refactor design and survived the refactor unreviewed, and the third-party behaviour claims were written from recollection of "how TCPDF works" instead of reading rbpdf's tag handlers — repeating the CRF-007/CRF-011 pattern of docs describing behaviour the code does not have, this time for an external library.

## Prevention

When a refactor changes what a module is responsible for, rewrite its module comment in the same edit. Every claim about a third-party library's behaviour in comments, ADRs or the wiki must name the file, class or method it was read from; if it was not read in that change, do not state it.

**Promoted to**: Not yet
