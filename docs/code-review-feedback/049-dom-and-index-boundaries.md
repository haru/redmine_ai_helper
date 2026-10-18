# CRF-049: Observer-added export links, observer root node and index 0 boundaries were missed

**Date**: 2026-10-17
**Source**: Local AI review (speckit-review-run, 6 parallel agents)
**Feature**: branch `feature/078-health-report-charts` (fix not yet committed)
**Files**: assets/javascripts/project_health/ai_helper_project_health_swap.js, ai_helper_health_report_chart.js, lib/redmine_ai_helper/health_report_chart/markdown_archive.rb
**Category**: edge-case
**Related**: CRF-040, CRF-042, CRF-045

## Feedback

- After regenerating on the project overview, two export link rows appeared: the MutationObserver re-added the POST-based links during generation, and `addReportExportLinks` only checked for duplicates inside the content container. The POST links render every chart as "no metrics".
- `renderWithin(node)` used `querySelectorAll`, which does not include the node itself, so a canvas added directly was never drawn.
- `MarkdownArchive.trim_text` received `parts[index - 1]`, i.e. `parts[-1]` (the last part) for index 0, trimming the body's leading newlines when the body ended with a directive.

## Original Code

```js
if (contentContainer.querySelector('.other-formats')) { return; }
```
```ruby
trim_text(part, parts[index - 1], parts[index + 1])
```

## Fix

`addReportExportLinks` removes the rows holding the `-dynamic` POST links before adding the saved report's links. `renderWithin` also checks `root.matches(...)`. `trim_text` gets `nil` as the previous part for index 0. Each fix has a regression test built from the real overview DOM (existing report and observer) or the boundary input.

## Root Cause

The AI tested the swap against a fresh DOM without the observer and the existing report the overview really has (the CRF-042 gap), so the interaction never showed. `querySelectorAll` and `array[index - 1]` were used as generic idioms without considering their boundary (the root itself, index 0 wrapping in Ruby).

## Prevention

- Test DOM-mutating code with every other script that mutates the same container (observers, re-initializers) loaded, starting from the page's real initial state.
- `querySelectorAll` on an observer's added node also checks the node itself.
- In Ruby, never index `array[i - 1]` without guarding `i.zero?`: negative indexes wrap.

**Promoted to**: Not yet
