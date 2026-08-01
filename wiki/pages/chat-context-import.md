---
title: Chat Context Import
type: component
sources: [S001]
updated: 2026-08-01
---

# Chat Context Import

When the gateway is mentioned, `ContextImporter` pulls in the surrounding
messages the bot has not yet seen, so answers can account for the ongoing
discussion (S001). Part of the [Chat Channel Gateway](./chat-channel-gateway-architecture.md).

## Import modes

`IncomingMessage#in_thread` (set by the adapter) drives the mode (S001):

- **Thread mode** (`in_thread` true): all thread messages after the cursor, no
  count/time limit.
- **Channel mode** (`in_thread` false *and* a brand-new conversation): top-level
  messages from the last 48 hours, max 20, older than the mention itself.
- **Otherwise** (reply-chain continuation, DM follow-ups): no import — following
  later channel messages into a thread-external conversation is out of scope (S001).

## Cursor persistence

The import position is stored in a new column
`ai_helper_channel_conversations.last_imported_message_key` (string, nullable):
the external message ID of the last *successfully imported* mention
(`IncomingMessage#message_ts`) (S001). It is treated as an **opaque
adapter-specific string** — Slack stores a `ts`, Discord a snowflake — and
ordering comparisons are delegated to the adapter's API parameters so the core
never compares heterogeneous ID schemes (S001). Because it survives in the DB,
imports are duplicate-free across gateway restarts. On failure the cursor is
**not** advanced, so the next mention safely retries the same range (S001).

## Persistence and hand-off to the LLM

Imported messages are saved as `AiHelperMessage(role: "context")`, appended in
speaking order, with `content = "{display name}: {text}"` (S001).
`AiHelperConversation#messages_for_openai` converts the `context` role for the
LLM: consecutive context messages are merged into one `user` message prefixed
with a header identifying them as other participants' messages not addressed to
the bot. Storing them as ordinary conversation messages means the second and
later mentions ride the existing `Llm#chat` path with no separate hand-off
route (DRY), and the reasoning is visible in Redmine's conversation history (S001).

## Failure handling (no silent fallback)

If history retrieval raises, `MessageHandler` logs `full_message` via
`ai_helper_logger.error`, prepends a `history_unavailable` notice to the answer
(saved into the message content too, so history and posted text match), and
still generates a normal answer with no prior context (S001). Per constitution
III this is *not* a banned silent fallback: the error is both logged and shown
to the user (S001).

## Fixed constants

| Constant | Value | Applies to |
|---|---|---|
| `CONTEXT_LOOKBACK_HOURS` | 48 | channel/DM top-level messages only |
| `CONTEXT_MESSAGE_LIMIT` | 20 | channel/DM top-level messages only |
| `CONTEXT_CHAR_LIMIT` | 20,000 | total chars of context passed to the LLM |

There is no settings screen; the values are fixed. When context messages exceed
`CONTEXT_CHAR_LIMIT`, the **oldest** are dropped from the LLM payload while the
stored records are left untouched. `CONTEXT_LOOKBACK_HOURS`/`CONTEXT_MESSAGE_LIMIT`
live in `ContextImporter`; `CONTEXT_CHAR_LIMIT` lives in `AiHelperConversation`,
each defined where it is used (S001).

## Related

- [Chat History APIs](./chat-history-apis.md) — where the messages come from.
