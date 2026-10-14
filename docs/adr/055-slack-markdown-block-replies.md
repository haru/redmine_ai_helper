# ADR-055: Slack replies as markdown blocks

**Date**: 2026-10-13
**Status**: Accepted (partially supersedes ADR-010: the Slack `<url|text>` link format)

## Context

The Slack adapter posted replies as plain `text`, which Slack renders as mrkdwn. The Markdown the agents write (headings, `**bold**`, lists, tables, `[text](url)` links) was therefore shown mostly as raw symbols, and tables were not shown at all. Slack's `markdown` block documents these elements, including "Renders as a formatted table." The `markdown_text` argument documents no table support and cannot be combined with `text` or `blocks` (`markdown_text_conflict`). Details and citations: `specs/074-slack-markdown-rendering/research.md` (R-001 to R-004).

## Decision

- `SlackAdapter#send_message`, `#post_progress` and `#update_progress` send `blocks: [{ "type": "markdown", "text": <body> }]` together with `text: <body>` (the notification fallback). `blocks` is passed as a JSON string through the existing form-encoded `api_call`. Long replies are split as before (3900 characters); each chunk gets its own block. A markdown block holds at most 12,000 characters per payload (research R-006), so a 3900-character chunk fits.
- `BaseAdapter#send_plain_message` is added and defaults to `send_message`. `SlackAdapter` overrides it to post `text` only. `MessageHandler#send_plain_reply`, which carries the failure notice, calls it, so the notice does not depend on the block being accepted.
- A rejected post (`invalid_blocks`, `msg_blocks_too_long`, ...) raises `SlackApiError` and is not retried in another format. When it happens after the answer was generated, `MessageHandler#handle` posts the `answer_delivery_failed` notice instead of `processing_failed`, because the answer exists but may be missing or cut off in the thread (spec FR-011). The log line says which of the two failed and names the channel type and thread.
- Blank text is never sent as a block: `markdown_params` raises `ArgumentError` for blank text, and `split_text` leaves out chunks that hold only whitespace.
- `IssueLinkFormatter::DISCORD` is renamed `MARKDOWN` and used by both Slack and Discord; `SLACK` is removed with no alias. Slack issue links are now `[#154](url)` instead of `<url|#154>`. Discord output is unchanged.

## Consequences

- Slack replies are formatted like the web sidebar, with tables, headings and lists.
- Slack and Discord share one link format and one pattern for `link_safe_cut`.
- Rendering of bare URLs, full-width tables, `& < >` and `chat.update` was verified on a real workspace; the table size limits are not documented, so an oversized table surfaces as `SlackApiError`.
- Messages that other bots post with `blocks` are still read from `text`; the bot's own posts are not imported.
- Known limitation: the split point can fall inside a code block or a table. Each chunk is rendered as its own block, so the code block or table renders broken across the two messages. Discord already behaves this way; spec 074 (Edge Cases) leaves it unchanged.
- Not verified: progress lines are joined with a single newline. Whether a markdown block shows them on separate lines was not checked on a real workspace.

## Alternatives Considered

- `markdown_text`: no documented table support and no `text` fallback.
- Converting Markdown to mrkdwn: mrkdwn has no headings, lists or tables.
- Sending the request as `application/json`: touches every API call and is not needed.
- A `plain:` keyword on `send_message`: changes the signature for every adapter.
- Re-sending a rejected post as plain text: a silent fallback, against the project's error-handling rule.
