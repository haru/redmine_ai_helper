# CRF-068: Redmine's Markdown preview return value was not consumed as a union

**Date**: 2026-10-21
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, simplify)
**Feature**: branch `080-office-attachment-markdown`
**Files**: lib/redmine_ai_helper/util/attachment_file_helper.rb, test/unit/util/attachment_file_helper_test.rb
**Category**: convention-violation
**Related**: CRF-022, CRF-050, CRF-055

## Feedback

errors review: `markdownized_preview_content` returns `String` or `nil` across the Redmine core boundary, but the code checked only `nil?` and then called `bytesize`/`byteslice`. Any other value (core change, another plugin's patch) would fail with `NoMethodError` far from the cause.

## Original Code

```ruby
bytes = attachment.markdownized_preview_content
return office_unconvertible_placeholder(attachment) if bytes.nil?
```

## Fix

`case bytes when nil … when String … else raise TypeError` (message names the attachment id and the class); the String branch moved to `office_markdown_attachment`. A test stubs a Symbol and expects `TypeError`.

## Root Cause

The AI read Redmine's source, saw that the method can only return a String or nil, and treated that as a guarantee instead of applying AGENTS.md's union rule (CRF-050), which exists precisely because "the other side can only return these" has been wrong before. The same rule was missed in CRF-055.

## Prevention

Every value returned from Redmine core or another library and documented as a union (including "X or nil") is consumed with `case`/`when` over each member and a raising `else`, even when the current source makes the else unreachable; add a test that drives the else.

**Promoted to**: Not yet
