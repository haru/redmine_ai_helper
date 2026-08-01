---
title: Chat History APIs
type: reference
sources: [S001]
updated: 2026-08-01
---

# Chat History APIs

How the Slack and Discord adapters actually retrieve surrounding messages for
[Chat Context Import](./chat-context-import.md). Both return newest-first and are
re-sorted to ascending by the adapter before returning (S001).

## Slack

| Purpose | API | Key params |
|---|---|---|
| Messages in a thread | `conversations.replies` | `channel`, `ts` (thread parent), `oldest`, `inclusive=false`, `limit=200`, `cursor` |
| Channel/DM top-level | `conversations.history` | `channel`, `latest` (the mention's own ts), `oldest` (48h ago), `inclusive=false`, `limit=20` |

- `oldest`/`latest` exclude the boundary unless `inclusive` is set, so
  `inclusive=false` is sent explicitly to avoid re-fetching known messages.
- Threads are fully imported: page while `response_metadata.next_cursor` is
  returned. Channel/DM completes in one call (≤20). `conversations.history`
  excludes thread replies (except `thread_broadcast`), matching "channel
  top-level messages" exactly (S001).
- **Extra scopes**: `channels:history`, `groups:history`, `mpim:history`,
  `users:read`. (`im:history` was already granted by 028.) Adding scopes
  requires reinstalling the app to the workspace (S001).
- **Display names**: payloads carry only user IDs; resolve via `users.info`
  (`profile.display_name` → `real_name` → `name`). To protect the +5s budget
  (SC-003), the adapter keeps an in-instance ID→name cache (FIFO, 500 entries,
  same style as `MAX_REPLY_TARGETS`). Other bots' messages carry `bot_id` and
  no `user`; use `username` (else `bot_profile.name`) (S001).

## Discord

| Purpose | API | Key params |
|---|---|---|
| Messages in a thread | `GET /channels/{thread_id}/messages` | `limit=100`, `before` (page backward) |
| Channel/DM top-level | `GET /channels/{channel_id}/messages` | `limit=20`, `before` (the mention's own ID) |

- Discord always returns descending order. Threads are fully imported, but
  paging stops as soon as an ID at or below the cursor is reached — a single
  **backward-pagination** path (no separate `after` path) keeps it simple, and
  incremental imports stop after the first page (S001).
- The 48h window is judged from the payload `timestamp` (ISO8601).
- **Display names** come from the payload — `member.nick` → `author.global_name`
  → `author.username` — so no extra API call is needed (unlike Slack) (S001).
- Message content availability depends on the
  [Message Content Intent](./discord-message-content-intent.md) (S001).

## Excluded messages (both tools)

Exclusion is decided in the adapter (mention/system-message syntax is
tool-specific). Excluded: the gateway's own messages; mention-questions to the
bot; join/leave-type system messages; empty bodies. Other bots' messages (e.g.
CI notifications) are **kept** as part of the discussion — Slack keeps `subtype`
in `[nil, "bot_message", "thread_broadcast", "file_share"]` (S001).

## Related

- [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md)
