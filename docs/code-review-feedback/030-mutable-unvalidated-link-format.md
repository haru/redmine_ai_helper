# CRF-030: IssueLinkFormatter::Format was a mutable Struct without validation

**Date**: 2026-10-13
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `074-slack-markdown-rendering`
**Files**: lib/redmine_ai_helper/chat_channel/issue_link_formatter.rb
**Category**: convention-violation
**Related**: CRF-009, CRF-015

## Feedback

`Format` is documented as a value object, but it was a positional `Struct` with setters and no checks, so `Format.new(nil, "x")` was accepted. AGENTS.md requires value objects to validate their invariants in `initialize`.

## Original Code

```ruby
Format = Struct.new(:renderer, :pattern) do
```

## Fix

`Format = Data.define(:renderer, :pattern)` with an `initialize` that raises `ArgumentError` unless `renderer.respond_to?(:call)` and `pattern.is_a?(Regexp)`. Tests cover both raises and immutability.

## Root Cause

The branch reshaped the constants but left the pre-existing type untouched; the AI did not re-check a value object it was already editing against the AGENTS.md value-object rule.

## Prevention

When a change touches a class documented as a value object, check it against the AGENTS.md rule (validate in `initialize`, raise `ArgumentError`) and prefer `Data.define` over `Struct` for immutable values.

**Promoted to**: Not yet
