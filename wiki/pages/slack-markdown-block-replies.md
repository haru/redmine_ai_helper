---
title: Slack Markdown Block Replies
type: decision
sources: [S047]
updated: 2026-10-13
---

# Slack Markdown Block Replies

Slack replies, guidance and progress messages are posted as `markdown` blocks
so headings, lists, tables and links render. Feature 074,
[ADR-055](../../docs/adr/055-slack-markdown-block-replies.md) (S047).

## Posting method

- `SlackAdapter#send_message`, `#post_progress` and `#update_progress` send
  `blocks: [{ type: "markdown", text: body }]` plus `text: body` (the
  notification fallback). `blocks` is a JSON string in the existing
  form-encoded `api_call`. Each 3900-character chunk gets its own block (S047).
- `markdown_text` was rejected: table support is not documented and it cannot
  be combined with `text` or `blocks`. Converting to mrkdwn was rejected:
  it has no headings, lists or tables (S047).
- The markdown block limit is 12,000 characters per payload; table size
  limits are not documented, so an oversized post raises `SlackApiError` and
  is never re-sent in another format (S047).
- Blank text is never sent as a block: `markdown_params` raises
  `ArgumentError`, and chunks holding only whitespace are left out (S047).
- Known limitation: a split point inside a code block or a table breaks its
  rendering across the two messages. Discord already behaves this way; spec
  074 leaves it unchanged (S047).

## Failure notices

`BaseAdapter#send_plain_message` defaults to `send_message`; Slack overrides
it to post `text` only. `MessageHandler#send_plain_reply` uses it, so the
notice is delivered even when the answer's block was rejected (S047). The
notice is `text` only, which Slack still reads as mrkdwn.

A failure after the answer was generated (for example a rejected block)
posts `answer_delivery_failed` instead of `processing_failed`, because the
answer may be missing or cut off in the thread. The log line names the
channel type and thread (S047).

## Issue links

`IssueLinkFormatter::DISCORD` was renamed `MARKDOWN` and is used by both
Slack and Discord; `SLACK` (`<url|#154>`) was removed. Slack links are now
`[#154](url)`, replacing the format in
[ADR-010](../../docs/adr/010-chat-channel-issue-link-rendering.md); Discord
output is unchanged (S047).

## Verified on a real workspace

Links, bare URLs, a full-width table, `& < >` and `chat.update` with blocks
all rendered as expected (S047). Whether progress lines joined with a single
newline show on separate lines was not checked.

Related: [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md),
[Chat Progress Message](./chat-progress-message.md).
