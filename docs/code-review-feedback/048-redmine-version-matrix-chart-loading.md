# CRF-048: Chart.js loading ignored Redmine 6.0 (no importmap) and the overview page

**Date**: 2026-10-17
**Source**: Local AI review (speckit-review-run, 6 parallel agents)
**Feature**: branch `feature/078-health-report-charts` (fix not yet committed)
**Files**: app/helpers/ai_helper_dashboard_helper.rb, app/views/ai_helper/project/_health_report.html.erb
**Category**: edge-case
**Related**: None

## Feedback

- `ai_helper_chart_heads` was called on two of the three pages that render report charts; the project overview (hook partial) never loaded `chart.min`, so its charts stayed blank on Redmine 6.x.
- The helper read the importmap's private `@packages` ivar, and on Redmine 6.0.x (`requires_redmine` >= 6.0.0) there is no importmap at all (`git show 6.0.0:Gemfile` has no importmap-rails), so `Rails.application.importmap` raises `NoMethodError`.

## Original Code

```ruby
return if Rails.application.importmap.instance_variable_get(:@packages).key?("chart.js")
```

## Fix

`return if Rails.application.respond_to?(:importmap) && Rails.application.importmap.packages.key?("chart.js")`, with a test for the no-importmap case. The overview partial calls `ai_helper_chart_heads` when it renders a stored report, with a test that the canvas and `chart.min` appear (mutation-checked).

## Root Cause

Research R-007 checked Redmine 7.0.1 and 6.1.3 only, and the AI treated those two as the supported matrix although `init.rb` allows 6.0.0. It took "three pages" from R-007 but listed only two call sites in the task, without grepping every view that calls `render_health_report_markdown`. It copied the private-ivar access from a quick probe instead of the gem's public API.

## Prevention

- When a feature depends on a Redmine/Rails asset or API, check it against the oldest version in `requires_redmine`, not only the versions researched; branch explicitly on its absence.
- When a helper must run on "every page that renders X", grep every caller of X and list each one in the task or test.
- Use a gem's public API (`attr_reader`) instead of `instance_variable_get`.

**Promoted to**: Not yet
