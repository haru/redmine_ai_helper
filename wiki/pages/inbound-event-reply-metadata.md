---
title: Inbound Event Reply Metadata
type: component
sources: [S018, S020]
updated: 2026-11-21
---

# Inbound Event Reply Metadata

How a reply finds the right event. Split from [Inbound Event Queue](./inbound-event-queue.md).

## Replying to the right event

`reply_metadata` (a JSON string) rides on the event row, and `InboundAdapter`
exposes `reply_metadata_for(thread_key:)`. The event is identified by **row
id**, carried on the message: `InboundEventMessage < IncomingMessage` adds
`event_id`, and `EventScopedHandler < MessageHandler` records it for the
duration of `#handle` — so `send_message`'s signature, `IncomingMessage` and
`MessageHandler` all stay untouched and existing adapter tests keep passing
(S018).

Identifying by thread position instead does not work (S018):

- one poll claims up to `POLL_BATCH_SIZE` rows, so several events in a thread
  turn `processed` at once;
- rows linger for `RETENTION_DAYS` while an in-memory cursor dies with the
  process — after a restart the first reply could pick up metadata from days
  ago (a lifetime asymmetry between row and cursor);
- `MessageHandler` calls `send_message` a second time to report a failed reply,
  so "one call consumes one event" over-advances the cursor.

Resolving through the event id makes the helper safe to call repeatedly: every
call during one reply returns the same value, and a reply never sees another
event's metadata — neither a sibling claimed in the same batch nor an event
answered days ago whose row is still retained. It returns `nil` outside a
reply, when the event carries no metadata, or when `thread_key` is not the
thread being answered (S020).

Adapters needing none of this simply never call the helper — the same "not
using it is the normal case" stance as `supports_history?` (S018).

> LINE's `replyToken` expires in tens of seconds, which the 2-minute freshness
> window plus LLM latency cannot fit. A LINE adapter is expected to reply with
> push messages, where `channel_id` alone determines the destination and no
> metadata is needed (S018).

## Related

- [Inbound Event Queue](./inbound-event-queue.md) — the main page.
