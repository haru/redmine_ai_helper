# CRF-051: Chart tests passed without the guard, diverged between Ruby and JS, and skipped call sites

**Date**: 2026-10-17
**Source**: Local AI review (speckit-review-run, 6 parallel agents)
**Feature**: branch `feature/078-health-report-charts` (fix not yet committed)
**Files**: test/unit/project_health_pdf_helper_test.rb, test/javascript/project_health/*.test.js, test/unit/lib/health_report_chart/*_test.rb, test/unit/project_health_partial_test.rb, test/functional/ai_helper_controller_test.rb, test/functional/ai_helper_dashboard_controller_test.rb
**Category**: test-gap
**Related**: CRF-006, CRF-010, CRF-024, CRF-033, CRF-042

## Feedback

- The PDF "add a page before a chart that does not fit" test passed with the guard removed: rbpdf's own page breaks produced the AddPage calls, and the recorder only wrapped `AddPage`, not the `add_page` alias the code calls (aliases bind to the original method, so `prepend` does not see them).
- The shared judgment table differed between Ruby and JS (#4 input) and the fence boundary cases existed only in Ruby.
- No test checked that the overview, the body partial and the original body actually draw charts (SF-015), that `health_report_content`'s `visible?` guard is reached (403 came from `authorize`), or that `health_report_saved` uses the latest report of the current user.
- The dynamic-import drawing path, SVG clockwise/large-arc flags, multiple directives, `#12` names, archive numbering and trailing newlines, and the streaming display with the real modules were untested.

## Original Code

```ruby
%i[Rect PieSector Circle setAlpha AddPage].each do |name| ... end
...
assert_operator calls_named(:AddPage).length, :>=, 2
```

## Fix

The recorder also wraps `add_page` and records only while enabled. The page-break tests call `render_pdf_chart` with the cursor placed just above the limit and assert AddPage comes first and the sector is near the top. Then the guard was removed to confirm the test fails. The same mutation check was done for the overview `chart.min` test, the `visible?` test, the `by_user` test and the end-to-end streaming test. The JS table now has the same boundary inputs as Ruby, and the contract table has rows #16–#20.

## Root Cause

The AI wrote assertions that described the expected state (two pages, a 403) without checking that the code under test is what produced it, and it did not run the test against a broken guard. Recorders built with `prepend` were assumed to see every call. The Ruby and JS tables were written at different times and not diffed.

## Prevention

- For every new guard or branch, run its test once with the guard removed and confirm it fails; when the expected outcome can also come from another layer (framework page breaks, `authorize`), arrange the input so only the guard can produce it.
- Call-recording doubles wrap both the CamelCase method and its snake_case alias.
- A test table shared across languages is kept as one list in the contract and copied row by row; diff the two test files against it before finishing.

**Promoted to**: AGENTS.md
