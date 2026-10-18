# CRF-053: Directives inside CommonMark HTML blocks made every report render fail with HTTP 500

**Date**: 2026-10-17
**Source**: Local AI review (speckit-review-run, 6 parallel agents; code + tests reproduced independently)
**Feature**: branch `feature/078-health-report-charts` (fix not yet committed)
**Files**: lib/redmine_ai_helper/health_report_chart/scanner.rb, test/unit/lib/health_report_chart/scanner_test.rb, test/unit/ai_helper_dashboard_helper_test.rb
**Category**: edge-case
**Related**: CRF-049, CRF-051

## Feedback

`Scanner.split` tracked only ``` / ~~~ fences. CommonMark HTML blocks of type 1-5 (`<pre>` `<script>` `<style>` `<textarea>`, `<!--`, `<?`, `<!DOCTYPE`, `<![CDATA[`) do not end at a blank line, so a directive line inside them was still split out and a `<p>marker</p>` was inserted inside the raw block. `md_to_html` then found no rendered marker and raised. Confirmed with the real renderer: `"Intro\n\n<pre>\n{{ai_helper_chart(status, version=1)}}\n</pre>\n"` raised RuntimeError; the same body saved to a report turned the project overview, dashboard detail, show, `health_report_content` and edit preview into HTTP 500 for every member.

The existing test at `ai_helper_dashboard_helper_test.rb:230` stubbed `md_to_html`, so this path could not be detected (CRF-051).

## Original Code

```ruby
elsif fence
  fence = nil if fence_closes?(line, fence)
  buffer << line << newline
```

## Fix

The Scanner (user-approved contract change, option (a)) now tracks HTML block types 1-5: each opening line records its end condition (closing tag, `-->`, `?>`, `>`, `]]>`); lines inside stay plain text and are never split into directives. The opening line may itself carry the end condition (`<pre>code</pre>`, `<!-- comment -->`). Fence lines never self-close (an opening fence always matches its own close pattern). Real-input tests (no `md_to_html` stub) cover every type plus the self-closing opening line.

## Root Cause

The Scanner was modelled on the two constructs the first implementation handled (backtick and tilde fences) and on the directive's own needs; the constructs of the surrounding language (CommonMark) that also swallow lines were never enumerated. The rendered-output test stubbed the one function whose contract the scanner depends on, so the mismatch was invisible.

## Prevention

When a scanner/parser branch treats "block constructs" specially, enumerate the full construct list from the language specification (for Markdown: CommonMark's block types) and cover each with a test that runs the real downstream renderer, not a stub of it (CRF-051).

**Promoted to**: Not yet
