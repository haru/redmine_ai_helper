# CRF-031: Slack rich and plain senders duplicated the chunk-posting loop

**Date**: 2026-10-13
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `074-slack-markdown-rendering`
**Files**: lib/redmine_ai_helper/chat_channel/adapters/slack_adapter.rb
**Category**: readability
**Related**: CRF-012, CRF-018

## Feedback

`send_message` and `send_plain_message` repeated the same `thread_ts_of` / `split_text` / `chat.postMessage` loop and differed only in the per-chunk parameters, so a future change to chunking could drift between them.

## Original Code

```ruby
thread_ts = thread_ts_of(thread_key)
split_text(text).each do |chunk|
  api_call("chat.postMessage", token: settings.bot_token, params: { channel: channel_id, thread_ts: thread_ts, text: chunk })
end
```

## Fix

A private `post_chunks(channel_id, thread_key, text) { |chunk| params }` holds the loop; each public method is one line.

## Root Cause

The plain sender was created by copying the existing `send_message` body and changing one line, instead of extracting the shared part.

## Prevention

When adding a method by copying an existing one and changing one expression, extract the shared body into a helper that takes the differing part as a block or argument.

**Promoted to**: Not yet
