---
title: Chat Processing Reaction
type: decision
sources: [S045, S046]
updated: 2026-10-13
---

# Chat Processing Reaction

> **Removed in feature 073 (S046).** The ⏳ reaction on the question message,
> the adapters' `show_processing` / `clear_processing`, `Gateway`'s reaction
> handling and `IncomingMessage#origin_channel_id` are gone; the only ⏳ left is
> the one on the progress message ([Chat Progress Message](./chat-progress-message.md)).
> The sections below describe what feature 072 did, for history.

Slack and Discord messages got a ⏳ reaction on receipt, removed once the
answer (or error) was posted. Feature 072, ADR-053 (S045).

## Why it was restored

PR #358 removed the old reaction because it was added in
`MessageHandler#handle` and **never removed** (Slack `reactions.add` only,
Discord `add_reaction` only), so ⏳ stayed after the answer. The removal
reason is inferred from the commits, not stated in the PR (S045). The restored
version pairs add and remove; adding alone was rejected as it reproduces the
bug (S045).

## Lifecycle

- **Show**: `Gateway#enqueue`, after the `@shutdown_requested` check and just
  before `@queue <<`. Messages dropped at shutdown never get a mark (S045).
- **Re-check**: the API call may take seconds, so `enqueue` checks the flag
  again; if shutdown began, it clears the mark and does not queue (S045).
- **Clear**: `Gateway#worker_loop` `ensure` around each message, so success,
  error replies, guidance replies and exceptions all clear it (S045).
- Show is called synchronously on the adapter's receive thread; a slow chat
  API can stall it for up to ~10 s (Discord more with 429 waits). Slack acks
  before processing, so no resend (S045).
- A gateway killed mid-processing can leave a ⏳; there is no start-up sweep
  (S045).

## Error policy

- The gateway rescues and logs (`ai_helper_logger.error`) every hook failure
  and continues with the answer (S045). This is a deliberate, narrow exception
  to the no-fallback rule.
- Slack: only `already_reacted` (add) and `no_reaction` (remove) are ignored;
  `SlackApiError` gained an optional `code`. `message_not_found`,
  `missing_scope`, `ratelimited` are logged (S045).
- Discord: nothing is ignored. Docs define 204 for both `PUT` and `DELETE`
  and say nothing about existing/missing reactions; 10014 Unknown Emoji means
  an unencoded emoji, not "no reaction" (S045). Whether `DELETE` on a missing
  reaction returns non-204 is left to manual verification (S045).

## Target channel

`IncomingMessage#origin_channel_id` (optional, defaults to `channel_id`) is the
channel the message lives in. Only a Discord mention inside an existing thread
passes the thread id. The old mutable `@actual_channels` map and `thread_key`
parsing were rejected (S045).

Related: [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md).
