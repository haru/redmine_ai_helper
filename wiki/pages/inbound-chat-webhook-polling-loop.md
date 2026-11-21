---
title: Inbound Webhook Polling Loop
type: decision
sources: [S018]
updated: 2026-11-21
---

# Inbound Webhook Polling Loop

Decision 3: the polling loop is `InboundAdapter#start`. Split from [Inbound Chat Webhook Ingest](./inbound-chat-webhook-ingest.md).

## 3. The polling loop is `InboundAdapter#start`

Polling is implemented as an adapter's `start`, so **`Gateway`,
`MessageHandler`, `IncomingMessage` and the existing adapters change by zero
lines** (S018).

- `Gateway#run` already runs each enabled adapter's `start` on its own thread
  and serializes `dispatch`ed messages through a single worker; "poll the DB"
  simply replaces "hold a WebSocket" inside that structure (S018).
- Per-adapter threads mean existing failure handling (`handle_adapter_exit`:
  one dead adapter doesn't stop the others; the last one dying ends the
  gateway) applies to inbound adapters unchanged (S018).
- `BaseAdapter#stop` (`@stopped = true` → `connection_ended!` → `close_socket`,
  a no-op when `@ws` is nil) already works for socketless adapters. Waiting on
  the existing `@connection_ended` queue via `BaseAdapter.timed_queue_pop`
  makes the poll sleep interruptible, so stop responsiveness matches the
  socket adapters (S018).

**Rejected**: one shared poller thread in `Gateway` (Gateway would have to route
channel types to adapters, i.e. know inbound exists); an empty `start` with
processing elsewhere (the thread exits immediately and `handle_adapter_exit`
concludes no adapters are alive, shutting the gateway down) (S018).

## Related

- [Inbound Chat Webhook Ingest](./inbound-chat-webhook-ingest.md) — the main page.
