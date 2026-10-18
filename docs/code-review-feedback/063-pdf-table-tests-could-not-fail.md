# CRF-063: PDF table tests could not fail against the bug they claimed to catch

**Date**: 2026-10-18
**Source**: Local AI review (speckit-review-run, `specs/079-fix-health-report-pdf-table/review-results.md`)
**Feature**: branch `bugfix/079-fix-health-report-pdf-table`
**Files**: test/functional/ai_helper_controller_test.rb, test/functional/ai_helper_dashboard_controller_test.rb, test/unit/project_health_pdf_helper_test.rb, test/test_helper.rb
**Category**: test-gap
**Related**: CRF-005, CRF-024, CRF-033, CRF-051

## Feedback

The review's tests findings (1-5): the table validation `text.lines.count { |line| line.strip.match?(/\A\|.*\|\z/) } == 0` was always 0 because `pdf_text` returns content-stream lines that start with `BT`/`q`, not drawn text, so the pre-fix bug (tables printed as Markdown text) could never be detected; four functional tests only repeated that vacuous assertion; `expects(:error).never` asserted the absence of a log the deleted rescue no longer emits; two tests stubbed `textilizable`, which the new code never calls; the `write_pdf_html` empty-HTML guard and the marker consumption order were tested on one side only; and nothing asserted screen and PDF agree when going through the controller.

## Original Code

```ruby
text = pdf_text(response.body)
assert_equal(0, text.lines.count { |line| line.strip.match?(/\A\|.*\|\z/) })
assert_no_match(/---/, text)
```

```ruby
RedmineAiHelper::CustomLogger.instance.expects(:error).with(regexp_matches(/Error processing content for PDF/)).never
```

```ruby
should "handle textilizable conversion errors gracefully" do
  self.stubs(:textilizable).raises(StandardError.new("Textilizable error"))
  ...
end
```

## Fix

- Added `PdfTextAssertions#pdf_text_runs` in `test/test_helper.rb`: it parses the actual `BT x y Td ... [(text)] TJ` operations (UTF-16BE strings, NUL padding removed) into `{x, y, text}` runs, so assertions act on the drawn text with its position.
- The four functional table tests now call the shared `assert_pdf_draws_two_tables`: it asserts the region exists (ten cell runs), no run starts with `|` or contains `|---`, both tables sit on separate header rows (a merged 5-column table would share one), and the column boundaries of the 3-column and the 2-column table differ.
- The hollow `expects(:error).never` lines were replaced with propagation tests (`assert_raises(RuntimeError) { get ... }`); the stale `textilizable` tests were deleted.
- New tests drive the empty-HTML guard, a marker nested in a `<blockquote>` (raise), consecutive and repeated directives consumed in order, and a controller-level screen/PDF cell comparison.
- Every new assertion was run once against the pre-fix implementation (develop's lib files) and with the guard / img-raise removed, and failed each time (CRF-051); the old implementation dropped the second table's data row, which the old assertions could not see.

## Root Cause

The AI judged its tests by whether they passed against the new code, never by whether they could fail against the old behaviour or with a guard removed. It also wrote the assertion against a convenient model of the PDF (plain text lines) instead of reading what rbpdf actually writes into the content stream — a single empirical dump (`Zlib::Inflate` + one `[(text)] TJ` line) would have shown the model was wrong. Tests inherited from the deleted fallback pipeline survived the refactor because nothing re-checked whether their stubs and expectations still pointed at existing code.

## Prevention

Before finishing a bug-fix branch: (1) run every new or changed test once against the pre-fix code and once with each new guard removed, and confirm it fails both times; (2) derive assertions about rendered output from the real rendered representation — dump it once (content stream, HTML, JSON) and parse that, never a hand-modelled shape; (3) after deleting a code path, grep the tests for its stubs, log messages and method names and delete or rewrite what no longer reaches the new code.

**Promoted to**: Not yet
