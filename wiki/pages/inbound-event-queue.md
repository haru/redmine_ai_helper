---
title: Inbound Event Queue
type: component
sources: [S018, S020]
updated: 2026-08-08
---

# Inbound Event Queue

What happens to a webhook event after
[the endpoint](./inbound-webhook-endpoint.md) stores it in
`ai_helper_inbound_events`, and how the gateway turns it into an answer. The
rationale is on [Inbound Chat Webhook Ingest](./inbound-chat-webhook-ingest.md)
(S018).

## States and de-duplication

Rows move one way: `pending → processed` or `pending → expired` (S018).

- **On receipt**: a UNIQUE index on `(channel_type, event_key)` is the dedup
  guard; a duplicate INSERT raises `ActiveRecord::RecordNotUnique`, which is
  caught and answered 200 as "already received". An application-level existence
  check cannot survive concurrent delivery, and external services resend
  whenever they don't get a 200 (S018).
- **On pickup**: `UPDATE … SET status='processed' WHERE id=? AND
  status='pending'` claims a row only if it updates exactly one row. That is
  atomic across a doubly-started or just-restarted gateway and holds no long
  transaction — unlike `SELECT … FOR UPDATE`, which would keep a row locked for
  the whole LLM call (S018).
- Marking `processed` **before** processing means a crash mid-answer leaves the
  event un-retried. Deliberate: in chat, a duplicate answer is worse than a
  missing one (S018).

## Tunables

`InboundAdapter` defines these constants, shared by every inbound adapter
(S020):

| Constant | Default | Meaning |
|---|---|---|
| `POLL_INTERVAL_SECONDS` | 2 | how often the gateway checks for pending events |
| `POLL_BATCH_SIZE` | 20 | rows claimed per poll |
| `FRESHNESS_LIMIT_SECONDS` | 120 | past this age at claim time, discard instead of answering |
| `RETENTION_DAYS` | 7 | how long a row survives, for deduplication, before deletion |
| `CLEANUP_INTERVAL_SECONDS` | 3600 | minimum gap between retention cleanups |

## Freshness and retention

- Right after a successful claim, an event older than `FRESHNESS_LIMIT_SECONDS`
  is set `expired`, logged, and dropped without dispatch. Judging at processing
  start applies one rule to recovery-from-downtime, backlog drain and normal
  traffic alike; judging before the claim would let several processes log the
  same expiry (S018). Replying "too old to answer" was rejected as noise (S018).
- The polling loop purges rows past `RETENTION_DAYS`, scoped to its own channel
  type — no cron required, and concurrent inbound adapters never collide on
  deletes (S018).

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

- [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md) — the other half:
  how events get here.
- [Developing an Inbound Chat Adapter](./inbound-adapter-development.md) — the
  guide these constants and helpers are written for.
- [Inbound Chat Webhook Ingest](./inbound-chat-webhook-ingest.md) — the
  decisions behind this design.
- [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md) —
  the adapter thread model the polling loop rides on.
