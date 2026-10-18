# CRF-050: New chart value objects and Chart|Unavailable results skipped the CRF-003/CRF-009 checks

**Date**: 2026-10-17
**Source**: Local AI review (speckit-review-run, 6 parallel agents)
**Feature**: branch `feature/078-health-report-charts` (fix not yet committed)
**Files**: lib/redmine_ai_helper/health_report_chart/chart.rb, palette.rb, directive.rb, resolver.rb, markdown_archive.rb, app/helpers/ai_helper_dashboard_helper.rb, lib/redmine_ai_helper/export/pdf/project_health_pdf_chart_helper.rb, project_health_pdf_helper.rb
**Category**: convention-violation
**Related**: CRF-003, CRF-009, CRF-015, CRF-030

## Feedback

- `Unavailable` validated nothing, while its sibling `Chart`/`Item` did.
- `Resolver.new` was documented as String or nil but silently treated any other value as "no metrics"; `Resolver#resolve` accepted non-Directives.
- `:hash`-kind counts were not type-checked: `"3"` or `nil` raised (500) while the fixed kinds returned `data_missing`.
- The three renderers checked one side of `Chart | Unavailable` and treated everything else as the other.
- `Palette::COLORS` froze only the outer array, `Item#rgb` shared it, `ChartType` definitions and `Chart#items` were mutable, `Directive` did not validate `target_value`, and the PDF helper did not check `options[:charts]`.

## Original Code

```ruby
@data = JSON.parse(metrics_json) if metrics_json.is_a?(String)
...
return "> #{resolved.message}" if resolved.is_a?(Unavailable)
svgs << SvgRenderer.render(resolved)
```

## Fix

`Unavailable::REASONS` plus message checks; `case metrics_json when String / when nil / else raise`; `count?` (non-negative Integer) for every kind; `case resolved when Chart / when Unavailable / else raise ArgumentError` in the helper, PDF and archive; deep freezes and `rgb.dup.freeze` with a 0..255 check; `Directive` requires a non-empty String (digits for versions); `charts.is_a?(Resolver)`. Every branch has a test.

## Root Cause

AGENTS.md already carries the rule (promoted from CRF-003/CRF-009). The AI applied it to the types it wrote first (`Directive`, `Chart`, `Item`) and stopped checking when it added the small `Unavailable` class and the consumers of the union return value. "Stored JSON" was treated as trusted internal data although it crosses a persistence boundary. `.freeze` was assumed to be deep.

## Prevention

- Apply the AGENTS.md value-object rule to every class in the change, including small ones added late; list each class and its invariants before writing tests.
- A method that returns a union is consumed with `case`/`when` over every member and an `else raise` — never `if A ... else` (treat B).
- Data read back from the database or a file is boundary input: validate element types the same way for every branch that reads them.
- Freeze nested constants element by element, and copy-then-freeze arrays a value object receives.

**Promoted to**: AGENTS.md
