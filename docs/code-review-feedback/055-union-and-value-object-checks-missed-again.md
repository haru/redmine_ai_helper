# CRF-055: Union returns and late-added value objects skipped the case/else and invariant checks again

**Date**: 2026-10-17
**Source**: Local AI review (speckit-review-run, 6 parallel agents)
**Feature**: branch `feature/078-health-report-charts` (fix not yet committed)
**Files**: lib/redmine_ai_helper/health_report_chart/scanner.rb, resolver.rb, chart.rb, markdown_archive.rb, app/helpers/ai_helper_dashboard_helper.rb, lib/redmine_ai_helper/export/pdf/project_health_pdf_chart_helper.rb
**Category**: convention-violation
**Related**: CRF-003, CRF-009, CRF-015, CRF-050

## Feedback

- The consumers of `Scanner.split`'s `String | Directive` (actually a 3-valued union: adjacency lookups return `nil` outside the array) used `if part.is_a?(String) ... else` — treating everything else as a Directive — so a `nil` would have been mis-consumed.
- `Resolver::Target` accepted invalid elements: `{"version_id": -1, "version_name": ""}` passed and was presented to the LLM as `version=-1 ()`, guaranteeing `invalid_arguments` for any directive that used it.
- `ChartType` definitions were unvalidated hashes, and `extract_values`'s `case kind` had no `else raise`: a typo'd kind silently turned every chart of that type into `data_missing`.

## Original Code

```ruby
parts.each do |part|
  if part.is_a?(String)
    ...
  else
    markers[part.source] = part # nil would land here too
  end
end
```

## Fix

Every `split` consumer is now a `case`/`when String` / `when Directive` / `when nil` (where adjacency allows it) / `else raise`. `Target` validates its invariants in `initialize` (positive integer version id, non-empty name) and raises `ArgumentError`. `ChartType` definitions are shape-checked at load time via a test, and `extract_values`'s `case` ends in `else raise`. Every new raise/guard branch has a test (including one run with the guard removed).

## Root Cause

The CRF-050 rule (promoted from CRF-003/CRF-009) was applied to the classes written early in the change; `Target` and the `ChartType` definitions were added later and smaller, and the `split` consumers were written with the idiomatic `if/else` because the union had grown a third member (`nil`) that the original two-valued pattern never mentioned.

## Prevention

List every union return value and every value object a change touches — including ones added late or returned as `nil` for "not applicable" — and check each against the AGENTS.md rule before writing the consuming code: `case`/`when` over every member plus `else raise`, invariants validated in `initialize` with `ArgumentError`.

**Promoted to**: Not yet
