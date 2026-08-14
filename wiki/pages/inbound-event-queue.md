---
title: Inbound Event Queue
type: component
sources: [S018, S020, S021]
updated: 2026-08-14
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

The `reply_metadata` column and `reply_metadata_for(thread_key:)` — resolved by
event **row id** rather than by thread position, and used by Teams to recover
`serviceUrl` — moved to
[Inbound Reply Metadata](./inbound-reply-metadata.md) when this page outgrew the
600-word page limit (S018, S020, S021).

## Read at receipt, too

The table is also queried on the *receiving* side. The Teams adapter reads the
newest row for its `channel_type`/`channel_id` inside `parse_events` to decide
whether a 1:1 chat continues an existing session — so `RETENTION_DAYS` doubles as
the horizon of that judgement, and an expired row simply means a fresh
conversation. No `channel_id` index was added for it: 7-day retention at chat
volumes makes a scan harmless, and the shared table stays unmodified (S021). See
[Teams 1:1 Session Window](./teams-one-to-one-session-window.md).

## Related

- [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md) — the other half:
  how events get here.
- [Inbound Reply Metadata](./inbound-reply-metadata.md) — the split-off half:
  how a reply finds its destination data.
- [Developing an Inbound Chat Adapter](./inbound-adapter-development.md) — the
  guide these constants and helpers are written for.
- [Inbound Chat Webhook Ingest](./inbound-chat-webhook-ingest.md) — the
  decisions behind this design.
- [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md) —
  the adapter thread model the polling loop rides on.
