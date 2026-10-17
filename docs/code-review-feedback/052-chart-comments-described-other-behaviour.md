# CRF-052: Chart comments and docs described behaviour the code does not have

**Date**: 2026-10-17
**Source**: Local AI review (speckit-review-run, 6 parallel agents)
**Feature**: branch `feature/078-health-report-charts` (fix not yet committed)
**Files**: lib/redmine_ai_helper/export/pdf/project_health_pdf_chart_helper.rb, project_health_pdf_helper.rb, lib/redmine_ai_helper/health_report_chart/scanner.rb, markdown_archive.rb, app/controllers/ai_helper_controller.rb, app/controllers/ai_helper_dashboard_controller.rb, config/routes.rb, assets/javascripts/project_health/ai_helper_chart_directive.js, ai_helper_health_report_chart.js, docs/adr/058-health-report-charts-placeholder-rendering.md, README.md, wiki/pages/health-report.md, specs/078-health-report-charts/research.md
**Category**: doc-comment
**Related**: CRF-005, CRF-011, CRF-032, CRF-037, CRF-043

## Feedback

- `with_chart_colors` claimed to set the alpha; the callers did.
- `project_health_markdown` claimed the zip holds chart SVGs; it never can (no metrics).
- `chart-<n>` was documented as "the directive's order of appearance", but unavailable directives use no number.
- The Scanner header said fenced lines never match "because the pattern anchors the line start"; one constant comment described two constants.
- `hidesPartialDirective` claimed to catch complete directives, the doughnut config said "half-transparent" (alpha is 0.2), the routes comment gave a reason that does not apply, and `health_report_content` listed a use that does not exist.
- ADR-058 summarised R-008 alternative (a) so that it read like the adopted design.

## Original Code

```ruby
# Fill with the shared alpha, then restore opacity for the border.
def with_chart_colors(pdf, rgb)
  pdf.SetFillColor(*rgb)
  pdf.SetDrawColor(*rgb)
  yield
end
```

## Fix

Comments were rewritten to match the code. The alpha handling moved into `draw_with_chart_colors` so its comment is now true. The numbering is stated as "drawable charts in order of appearance" in R-010, README, wiki, ADR and the archive comment (the user chose this rule). The ADR alternative names `project_health_metadata` as in research.

## Root Cause

Comments were written from the intended design while the code was being split and refactored (helpers moved into blocks, the archive changed to number drawable charts only), and they were not re-read after the code settled. The ADR summary paraphrased research instead of copying its wording (CRF-032 applies).

## Prevention

After the final refactor of a change, re-read every comment and doc sentence that names a method, a count or an order in the diff, and check it against the code line it describes. When the code's rule differs from the spec's wording, either change the code or update spec, docs and comments together in the same change.

**Promoted to**: Not yet
