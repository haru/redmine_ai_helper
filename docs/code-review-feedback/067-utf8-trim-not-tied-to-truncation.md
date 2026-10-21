# CRF-067: UTF-8 trailing-byte repair was not tied to Redmine's cut and broke on short input

**Date**: 2026-10-21
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, simplify)
**Feature**: branch `080-office-attachment-markdown`
**Files**: lib/redmine_ai_helper/util/attachment_file_helper.rb, test/unit/util/attachment_file_helper_test.rb
**Category**: edge-case
**Related**: CRF-051, CRF-063

## Feedback

errors/tests/code reviews: (a) `valid_utf8_prefix` removed an incomplete last character from every conversion result, although only Redmine's `byteslice` at the output limit can produce one; below the limit it silently repaired a damaged cache. (b) For results shorter than 3 bytes, `bytes.byteslice(bytes.bytesize - cut, cut)` used a negative index (`"\xFF".b.byteslice(-2, 3)` is nil), raising `NoMethodError` instead of the documented `EncodingError`. (c) Replacing the `incomplete_utf8_sequence?` guard with `true`, or dropping its continuation-byte check, left every test green: the existing inputs raised either way.

## Original Code

```ruby
def valid_utf8_prefix(bytes, attachment)
  (0..MAX_INCOMPLETE_UTF8_BYTES).each do |cut|
    tail = bytes.byteslice(bytes.bytesize - cut, cut).bytes
```

## Fix

`valid_utf8_prefix(bytes, attachment, truncated:)` trims only when the result reached the limit, with `max_cut = truncated ? [MAX_INCOMPLETE_UTF8_BYTES, bytes.bytesize].min : 0`. New tests: incomplete last character below the limit, invalid last byte that is not a lead byte, lead byte followed by a non-continuation byte, 1–2 byte invalid results (limit replaced via `const_set`), 2-byte character cut. Each guard was removed once and its test failed.

## Root Cause

Research R-007 described the repair without the condition that FR-006 states ("cut by Redmine's truncation"), and the AI implemented R-007 instead of re-reading the FR. The byte-arithmetic was written for the realistic case (100 KB results) without asking what happens when `cut > bytesize`. The tests were chosen to show that bad input raises, not to show that each guard is the thing that makes it raise (CRF-051 was not applied to this guard).

## Prevention

A repair of malformed input is applied only under the condition that explains the malformation (here: the result reached the cut limit), and the condition is a parameter of the repair method. Every index computed as `size - n` is bounded by `size`, with a test for input shorter than `n`. For each guard, write one input that only that guard rejects.

**Promoted to**: Not yet
