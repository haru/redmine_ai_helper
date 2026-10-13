# CRF-029: Slack markdown tests skipped the progress payload end to end and compared JSON strings

**Date**: 2026-10-13
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `074-slack-markdown-rendering`
**Files**: test/unit/chat_channel/message_handler_test.rb, test/unit/chat_channel/adapters/slack_adapter_test.rb, test/unit/chat_channel/issue_link_formatter_test.rb
**Category**: test-gap
**Related**: CRF-010, CRF-017, CRF-024

## Feedback

- The real-adapter progress test from `MessageHandler#handle` checked only `text`, not `blocks` (FR-007, CRF-010).
- Several tests compared serialized `blocks` JSON strings, tying them to key order and spacing.
- The `markdown_params` guard was tested only by calling the private method through `send`.
- V-02 used a weak negative regex instead of comparing the whole output.
- No test drove the Discord error notice through the real adapter, or an empty LLM answer to the Slack payload.

## Original Code

```ruby
assert_equal "#{@planning}\n- Reading the issue...", forms[2].last["text"]
"blocks" => [ { type: "markdown", text: "Planning" } ].to_json
```

## Fix

The progress e2e test asserts the parsed `blocks` of the post, both updates and the answer. Payload tests parse `blocks` (`blocks_of`) and compare against a Hash helper. Guard tests go through public methods. V-02 uses `assert_equal`. New tests cover the Discord error notice and the empty-answer path.

## Root Cause

The AI extended existing tests minimally (adding the new field only to unit tests) and reused the implementation's own `to_json` expression as the expected value, so the tests mirrored the code instead of the payload Slack receives.

## Prevention

When a feature changes a request payload, update the top-level end-to-end test for every message kind it touches (answer, progress post, progress update, notice) to assert the new field. Compare structured payload fields after parsing, never as serialized strings, and drive private guards through public methods.

**Promoted to**: Not yet
