# CRF-027: Answer delivery failure reported to the user as a generation failure

**Date**: 2026-10-13
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `074-slack-markdown-rendering`
**Files**: lib/redmine_ai_helper/chat_channel/message_handler.rb, config/locales/en.yml, config/locales/ja.yml
**Category**: error-handling
**Related**: CRF-014, CRF-022

## Feedback

Markdown blocks added a new failure: the answer is generated and saved, then Slack rejects the post (`invalid_blocks`, ...). `#handle` still sent "An error occurred while generating the answer", which is wrong, and after a partial split post the user could not tell the answer was cut off. The log line did not name the channel or thread.

## Original Code

```ruby
rescue => e
  ai_helper_logger.error "chat channel processing failed: #{e.full_message}"
  send_plain_reply(message, guidance(:processing_failed, user), user)
```

## Fix

`#handle` keeps the generated `answer` in a local; the rescue sends `answer_delivery_failed` when it is set and `processing_failed` otherwise. Both log lines name `channel_type` and `thread_key`. Spec 074 gained FR-011.

## Root Cause

The change added a new way for the existing `reply` call to fail but reused the existing catch-all notice without asking whether its text was still true for the new failure. The spec only said the notice must avoid the block format (FR-010), not what it should say.

## Prevention

When a change adds a new failure mode to an existing call, re-read the user-facing message and the log line in the rescue that will catch it, and confirm both are still accurate. Distinguish "work failed" from "result could not be delivered" in user notices, and name the resource (channel/thread id) in the log line.

**Promoted to**: Not yet
