# CRF-057: Resolver guards were unreachable from tests and the SSE contract was tested only through stubs

**Date**: 2026-10-17
**Source**: Local AI review (speckit-review-run, 6 parallel agents)
**Feature**: branch `feature/078-health-report-charts` (fix not yet committed)
**Files**: lib/redmine_ai_helper/health_report_chart/resolver.rb, test/unit/lib/health_report_chart/resolver_test.rb, lib/redmine_ai_helper/export/pdf/project_health_pdf_chart_helper.rb, test/unit/lib/export/pdf/project_health_pdf_chart_helper_test.rb, test/functional/ai_helper_controller_test.rb, app/controllers/ai_helper_controller.rb
**Category**: test-gap
**Related**: CRF-010, CRF-017, CRF-024, CRF-051

## Feedback

- `extract_values` on `progress_metrics: "n/a"` raised a TypeError from `dig` instead of returning `data_missing` (a real bug the test agent hit): the `issue_statistics` branch had an `is_a?(Hash)` guard, the progress branch did not.
- The guards for a non-Hash `issue_statistics` (`resolver.rb:173`) and non-Hash elements in the metrics arrays (`:89`, `:127`) were unreachable: removing them broke no test.
- The PDF space check was tested only for the bar form; deleting it for stacked (`:100`) and tile (`:130`) broke nothing.
- The `health_report_saved` contract — "the event carries the same string `Llm#project_health_report` saved" — was asserted only with `Llm` stubbed, and the no-event-on-LLM-exception path had no test.
- The overview partial's `persisted_report: nil` branch was not covered: swapping in another record's metrics broke no assertion.

## Fix

The progress branch got the same `is_a?(Hash)` guard as `issue_statistics` and now returns `data_missing`. Tests drive every previously unreachable guard (non-Hash `issue_statistics`, non-Hash array elements), assert the stacked and tile PDF space checks, exercise the SSE contract through the real `Llm`/`ProjectAgent` (only `think_chat` and the metrics tools stubbed) and verify no event is sent when the LLM raises, and pin the `persisted_report: nil` render with real input (per CRF-051/CRF-042).

## Root Cause

Tests were derived from the happy-path input shapes the code was written against, so guards added "for safety" had no test that could reach them, and the cross-layer property (string equality across `Llm` → controller → SSE payload) was tested at a layer whose boundary was stubbed away.

## Prevention

For every `is_a?`/nil guard, write the test first with the malformed input that only that guard can catch (delete the guard and watch the test fail). When a property spans layers (agent output → controller → browser event), test it from the top-level entry point with only the true externals (LLM API, tools) stubbed — never stub the layer whose contract is the property.

**Promoted to**: Not yet
