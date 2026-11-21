---
title: Inbound Webhook Event Normalization & Failures
type: component
sources: [S020]
updated: 2026-11-21
---

# Inbound Webhook Event Normalization & Failures

The normalized event and failure handling. Split from [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md).

## The normalized event

`parse_events` returns **exactly** these keys; an event carrying anything else
is logged as an error and skipped, because it cannot be stored (S020):

| Key | Required | Meaning |
|---|---|---|
| `:event_key` | yes | external event id — the dedup key |
| `:text` | yes | question body, mention markup already stripped |
| `:channel_id` | yes | channel or DM identifier |
| `:thread_key` | yes | thread identifier |
| `:message_ts` | no | per-message id, where the platform has one |
| `:dm` | no | direct-message flag (default `false`) |
| `:in_thread` | no | reply-in-thread flag (default `false`) |
| `:reply_metadata` | no | platform data needed to reply; JSON-encoded into the column by `AiHelperInboundEvent#reply_metadata=` |

The bot's own messages are never included, and speaker identity goes into
neither `:text` nor `:reply_metadata` — the plugin records only the configured
service account that answers, as it already does for outbound adapters (S020).

## Failure handling

Errors here favor **not** making the platform retry forever (S020):

- An unparseable request (malformed JSON, unexpected shape) should raise; the
  controller catches it, logs the full backtrace, and still answers `200`.
- A single event that cannot be stored is logged with its backtrace and
  skipped; the other events of that delivery are still stored and the delivery
  still gets its `200`.

## Related

- [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md) — the main page.
