---
title: Inbound Chat Webhook Ingest
type: decision
sources: [S018, S019]
updated: 2026-08-08
---

# Inbound Chat Webhook Ingest

Feature 044-inbound-chat-webhook adds the foundation for services that **push** messages over a
webhook (LINE, Microsoft Teams) instead of accepting an outward socket
connection like Slack/Discord do. Those platforms deliver events *only* by
POSTing to a URL registered with them, so building on ADR-006 unchanged would
leave them unsupportable (S019). Concrete service adapters are out of scope;
the base is proven with a test-only reference adapter (S018), and writing a
real one means subclassing `InboundAdapter` with `verify_request`,
`parse_events` and optionally `challenge_response`, touching no core code
(S019). Decisions 1–2 below are recorded as **ADR-017**
(`docs/adr/017-inbound-chat-webhook-gateway.md`, Accepted 2026-08-08) (S019).

## 1. The endpoint lives in the Redmine web process

A Rails controller (`AiHelperChatWebhookController`, `POST
/ai_helper/chat_webhook/:channel_type`) receives events; the gateway process
embeds **no HTTP server** (S018).

- Reuses Redmine's existing public HTTPS URL, TLS termination and reverse-proxy
  config, so operators expose no new port (S018).
- Keeps ADR-006's split intact: the gateway stays a resident process dedicated
  to receiving and serializing work, rather than gaining a public surface (S018).
- The endpoint never generates a response, so Puma's multithreading cannot break
  the `User.current` permission isolation ADR-006 depends on (S018).

**Rejected**: an HTTP server inside the gateway (forces new port/TLS/proxy setup
on operators); calling the LLM directly in the endpoint (concurrent execution
breaks `User.current` isolation — ruled out on sight) (S018).

## 2. Handoff is a database table, polled

Verified events are normalized into `ai_helper_inbound_events` and the gateway
polls for unprocessed rows every 2 seconds by default (S018).

- The only shared storage a Redmine plugin may assume is Redmine's own
  database; Redis must not become an install requirement. Solid Queue and
  Redmine's own mail intake use the same "DB as queue" pattern (S018).
- Worst-case handoff delay equals the poll interval, well inside the 5-second
  target (S018).

**Rejected**: PostgreSQL `LISTEN/NOTIFY` (Redmine also supports MySQL, and a
persistent connection complicates the gateway); ActiveJob (Redmine's default
`:async` adapter runs inside the web process, unreachable from a separate
gateway — the same reason ADR-006 already rejected it); a file-based queue (not
shareable across multiple Redmine nodes) (S018).

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

## Consequence for ADR-006

Decision 1 changes who needs a public URL, so ADR-017 amends the scope of
ADR-006's "no public URL" premise instead of editing that append-only document
(S018, S019). ADR-006 decision 5's permission separation is untouched — the
internet-reachable web process still never runs an LLM request (S019). The
scope amendment, its negative consequence and the framing it rejects are on
[Public URL Scope for Chat Adapters](./public-url-scope.md).

## Related

- [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md) — the receiving
  controller: anonymous access, signature verification, challenge responses.
- [Inbound Event Queue](./inbound-event-queue.md) — the mechanics these
  decisions produce: states, claiming, expiry, retention, reply metadata.
- [Public URL Scope for Chat Adapters](./public-url-scope.md) — what ADR-017
  changed about ADR-006's premise, and what it deliberately did not.
- [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md) —
  the core/adapters structure this plugs into.
