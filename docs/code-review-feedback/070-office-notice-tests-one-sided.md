# CRF-070: Office notice and metadata tests covered only the positive side or one layer

**Date**: 2026-10-21
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, simplify)
**Feature**: branch `080-office-attachment-markdown`
**Files**: test/unit/util/attachment_file_helper_test.rb, test/unit/util/issue_json_test.rb, test/unit/util/wiki_json_test.rb, test/unit/tools/file_tools_test.rb
**Category**: test-gap
**Related**: CRF-051, CRF-057

## Feedback

tests review: no test showed that ordinary links (`[t](x.png)`) or tags like `<imgx>` do *not* get the image notice (FR-014's "must not"); the no-text judgement was tested only with Markdown image syntax, so dropping `HTML_IMAGE_PATTERN` from it passed; success paths did not assert that no warn/info log is written; FR-011 (`type: "document"`) was tested only in the helper, not in `IssueJson`/`WikiJson`; FR-010 with a failed conversion was not tested through `analyze_content_files`; the upper-case extension test could not fail on what its name claimed.

## Original Code

```ruby
should "not add a notice when there is no image reference" do
  att = office_attachment("x.docx", previewable: true, content: "just text")
```

## Fix

Added false-positive cases for the image patterns, an HTML-only no-text case, `expects(:warn/:info).never` on the success test, `type: "document"` tests in both JSON helpers, an `analyze_content_files` test for a nil conversion, and renamed the upper-case test to what it checks. Removing `!`, `\b` or the HTML pattern from the no-text check now fails a test.

## Root Cause

Tests were written from the spec's positive acceptance scenarios; "must not" clauses and the second pattern of a two-pattern rule were not turned into inputs, and the cross-layer rule (CRF-010) was applied to one entry point only.

## Prevention

For every "must not" in an FR, write a near-miss input that a slightly broken regex or condition would accept. For a rule built from N alternatives (patterns, branches), each alternative gets its own input in every place the rule is used. Each FR that names a caller layer gets one test at that layer.

**Promoted to**: Not yet
