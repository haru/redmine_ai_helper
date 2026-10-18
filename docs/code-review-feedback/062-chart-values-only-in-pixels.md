# CRF-062: Chart labels and counts were available only as pixels

**Date**: 2026-10-18
**Source**: GitHub Copilot (PR #528)
**Feature**: branch `feature/078-health-report-charts` / PR #528 (fix not yet committed)
**Files**: app/views/ai_helper/project/_health_report_chart.html.erb, test/unit/ai_helper_dashboard_helper_test.rb
**Category**: other (accessibility: information conveyed only visually)
**Related**: None

## Feedback

The canvas exposed only the chart title (`aria-label`) to screen readers. Category names and counts existed only in pixels and a data attribute, and the prompt discourages repeating the breakdown in prose (https://github.com/haru/redmine_ai_helper/pull/528#discussion_r4305466627).

## Original Code

```erb
<canvas role="img" aria-label="<%= resolved.title %>"
        data-ai-helper-chart="<%= ... %>"></canvas>
```

## Fix

A `<ul class="hidden-for-sighted">` (Redmine's existing class) listing every item label, which already includes its count, follows the chart container. It stays outside the container because Chart.js sizes the canvas from a container dedicated to it. Ids and `aria-describedby` were not used, because the rendered body must stay deterministic.

## Root Cause

`role="img"` + `aria-label` was treated as sufficient accessibility for a canvas. The design deliberately moved numbers out of the prose (the LLM is told the chart carries them), which removed the only text alternative, and no one checked what a non-visual reader still receives.

## Prevention

When a feature moves information into a visual-only element (canvas, SVG, image), provide the same information as text in the DOM (Redmine's `.hidden-for-sighted` if it should not be seen) and assert it in the rendering test.

**Promoted to**: Not yet
