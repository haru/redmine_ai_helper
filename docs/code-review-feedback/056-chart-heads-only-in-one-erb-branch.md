# CRF-056: Chart heads were loaded only in the saved-report branch of the overview partial

**Date**: 2026-10-17
**Source**: Local AI review (speckit-review-run, 6 parallel agents)
**Feature**: branch `feature/078-health-report-charts` (fix not yet committed)
**Files**: app/views/ai_helper/project/_health_report.html.erb, app/controllers/ai_helper_controller.rb, test/unit/project_health_partial_test.rb
**Category**: edge-case
**Related**: CRF-048, CRF-049

## Feedback

`_health_report.html.erb` called `ai_helper_chart_heads` (which loads `chart.min`) only in the branch that renders a saved report. The placeholder and error branches render without it. After a generation finished on the project overview (Redmine 6.0/6.1, no importmap), the client-side swap fetched the server-rendered body into that same DOM and `import("chart.js")` failed, leaving every chart blank — violating FR-008/SC-004.

Additionally, the functional render through `AiHelperController#project_health` raised: Redmine runs with `include_all_helpers = false` and the controller declared only `AiHelperHelper`, so `ai_helper_chart_heads` (defined in `AiHelperDashboardHelper`) was undefined on that path.

## Original Code

```erb
<% if persisted_report %>
  <%= ai_helper_chart_heads %>
  ...
<% else %>
  <%= render partial: "ai_helper/project/placeholder" %>
<% end %>
```

## Fix

`ai_helper_chart_heads` is now called unconditionally at the top of the partial, matching the dashboard side. `AiHelperController` declares `helper AiHelperDashboardHelper` so the partial renders on the controller path. Tests cover the placeholder state (chart heads present, no canvas) and the stub-free functional render.

## Root Cause

The partial's branches were treated as independent render paths, and only the one that immediately displays charts was wired; the swap moves server-rendered chart markup into the DOM rendered by the *placeholder* branch, a state the branch structure hides. The helper-resolution requirement (`include_all_helpers = false`) was known for `ProjectsHelper` (patched) but not checked when the same partial gained a second rendering controller.

## Prevention

When a partial gains content that needs JS assets or helpers, call the asset loader unconditionally at the partial's top (all branches share one DOM lifetime) and enumerate every controller that renders the partial, declaring each helper it uses — `include_all_helpers` is off in Redmine.

**Promoted to**: Not yet
