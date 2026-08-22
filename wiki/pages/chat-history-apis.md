---
title: Chat History APIs
type: reference
sources: [S001, S024]
updated: 2026-08-14
---

# Chat History APIs

How the Slack, Discord and Teams adapters actually retrieve surrounding messages for
[Chat Context Import](./chat-context-import.md). All three hand the core ascending
order, but they arrive there differently: Slack and Discord return newest-first and
the adapter reverses the page (S001), while Graph's ordering is not relied on at
all — the Teams adapter sorts by numeric message id (S024).

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

## Teams (Microsoft Graph v1.0)

| Purpose | API | Key params |
|---|---|---|
| Messages in a thread | `GET /teams/{aadGroupId}/channels/{channelId}/messages/{rootId}/replies` | `$top=50`, follow `@odata.nextLink` until past the `after` cursor |
| Channel top-level | `GET /teams/{aadGroupId}/channels/{channelId}/messages` | `$top={limit}`, one page, filtered to `createdDateTime >= since` and `id < before` |

- On a first import (`after` empty) the thread's root message is fetched
  separately via `GET …/messages/{rootId}` (S024).
- Tokens: `POST https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/token`
  with `scope=https://graph.microsoft.com/.default`, same App ID and secret as
  the bot. Access needs the RSC permission `ChannelMessage.Read.Group` (S024).
- **Display names** come from `from.user.displayName` in the payload, so no
  resolution call is needed (S024).
- 1:1 chats return `[]` without any call, and failures (403 for missing
  permission, 404, anything else) are raised so the answer can carry the
  `history_unavailable` notice — see
  [Teams History via Microsoft Graph](./teams-graph-history.md) (S024).

## Excluded messages

Exclusion is decided in the adapter (mention/system-message syntax is
tool-specific). Excluded: the gateway's own messages; mention-questions to the
bot; join/leave-type system messages; empty bodies. Other bots' messages (e.g.
CI notifications) are **kept** as part of the discussion — Slack keeps `subtype`
in `[nil, "bot_message", "thread_broadcast", "file_share"]` (S001).

## Related

- [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md)
- [Teams History via Microsoft Graph](./teams-graph-history.md) — why Teams
  pulls from Graph rather than consuming pushed messages.
