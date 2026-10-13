# CRF-026: Slack markdown body guard let blank and non-String text through

**Date**: 2026-10-13
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `074-slack-markdown-rendering`
**Files**: lib/redmine_ai_helper/chat_channel/adapters/slack_adapter.rb
**Category**: edge-case
**Related**: CRF-009, CRF-013

## Feedback

`markdown_params` rejected only empty text, so a chunk of only spaces was still sent as a markdown block. `split_text` strips only leading newlines, so an answer just over 3900 characters whose tail is whitespace produced such a chunk. `send_message(text: nil)` raised `NoMethodError` from `split_text` before the `ArgumentError` guard ran. The guard message also embedded `text.inspect`, which can be large.

## Original Code

```ruby
raise ArgumentError, "text must be a non-empty String, got #{text.inspect}" unless text.is_a?(String) && !text.empty?
...
chunks << remaining unless remaining.empty?
```

## Fix

`markdown_params` raises separately for a non-String (naming `text.class`) and for blank text. A new `post_chunks` helper checks `is_a?(String)` before splitting. `split_text` drops chunks that hold only whitespace. Tests drive the guard through `send_message`, `post_progress` and `update_progress`.

## Root Cause

The guard was written for the obvious invalid value (empty string) and placed in the innermost builder. The AI did not trace which inputs reach it through `split_text`, which runs first and assumes a String, and did not consider whitespace-only remainders produced by the splitter.

## Prevention

When adding an input guard, list every public entry point that reaches it and check that no earlier step dereferences the value; test the guard through those entry points. For text bound for a chat or LLM API, reject blank (`strip.empty?`), not only empty, and make any splitter drop whitespace-only pieces. Name the class, not the value, in type errors.

**Promoted to**: Not yet
