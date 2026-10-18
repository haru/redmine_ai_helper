# CRF-065: Screen renderer kept a fast path that bypassed the shared conversion

**Date**: 2026-10-18
**Source**: Local AI review (speckit-review-run, `specs/079-fix-health-report-pdf-table/review-results.md`)
**Feature**: branch `bugfix/079-fix-health-report-pdf-table`
**Files**: app/helpers/ai_helper_dashboard_helper.rb
**Category**: convention-violation
**Related**: CRF-060

## Feedback

The review's comments finding 9(a): ADR-061's first Decision bullet says the screen (`render_health_report_markdown`) and the PDF both call the one shared conversion `AiHelperHelper#health_report_html_with_chart_markers`, and the spec contract says "render_health_report_markdown は必ずこれを使う" — but the screen still had a pre-refactor early return that called `linkify_issue_references(md_to_html(text))` directly whenever the body had no chart directive.

## Original Code

```ruby
parts = RedmineAiHelper::HealthReportChart::Scanner.split(text.to_s)
return linkify_issue_references(md_to_html(text)) unless parts.any?(RedmineAiHelper::HealthReportChart::Directive)

resolver = RedmineAiHelper::HealthReportChart::Resolver.new(report&.metrics)
html, markers = health_report_html_with_chart_markers(parts)
```

## Fix

The early return was removed: every body — with or without directives — goes through `health_report_html_with_chart_markers`, so the ADR's "one conversion, both call sites" statement is literally true. The output is unchanged (the helper returns exactly `linkify_issue_references(md_to_html(text)).to_s` for a directive-free body), which the existing equivalence tests still pin.

## Root Cause

The refactor introduced the shared helper but kept the old fast path for the "simple" case because the output happened to be identical. The AI did not re-read the ADR and contract it had just written, which both declare the shared call unconditional; equivalence of output was treated as equivalence of mechanism.

## Prevention

When an ADR or contract states that two call sites share one helper, grep both call sites in the same change and remove any path that bypasses the helper — including fast paths for inputs the helper handles trivially. Output equality does not license a second mechanism.

**Promoted to**: Not yet
