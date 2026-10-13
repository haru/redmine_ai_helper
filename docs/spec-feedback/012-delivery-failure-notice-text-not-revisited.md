# SF-012: Kept the "error while generating" notice for a new answer-delivery failure

**Date**: 2026-10-13
**Feature**: specs/074-slack-markdown-rendering (branch `074-slack-markdown-rendering`)
**Artifact**: spec.md, data-model.md, contracts/slack_markdown_message.md
**Category**: scope-gap
**Related**: SF-011

## Feedback

A review of the implementation found that Slack can now reject the answer post itself (`invalid_blocks`, ...) after the answer was generated and saved. The user then received the generic notice "An error occurred while generating the answer", which is wrong, and after a partial split post had no way to know the answer was cut off. Asked how to handle it, the user chose to add a dedicated notice.

## What the AI Wrote

spec.md Edge Cases: "When Slack rejects the formatted answer post ... the user receives the unformatted error notice (FR-010)." FR-010 only required that the notice not use the markdown block. data-model.md fixed the notice text to `ai_helper.chat_channel.errors.processing_failed`.

## Correction

- spec.md: added FR-011. When posting the answer fails after it was generated (including a failure midway through a split post), the notice is `answer_delivery_failed`, not `processing_failed`. The log records the failure kind, the chat tool type and the thread. The Edge Case and the Key Entity "error notice" were updated to list both notices.
- data-model.md: the error notice text now names both keys.
- contracts C-7: `#handle`'s rescue picks the key by whether the answer was generated, and the log names `channel_type` and `thread_key`.

## Root Cause

The spec introduced a new way for the answer post to fail (Slack rejecting the block) and handled only *how* the notice is sent (FR-010, after SF-011). It reused the existing notice without re-reading its text ("error while generating the answer") against the new failure, which happens after generation. The AI treated the notice as a fixed constant instead of a statement that must stay true for every failure that reaches it.

## Prevention

When a spec adds a new failure mode to an existing operation, list every user-facing message and log line that the failure reaches and check that each is still true for it. In particular, separate "the work failed" from "the result could not be delivered" and state which message each case gets.

**Promoted to**: Not yet
