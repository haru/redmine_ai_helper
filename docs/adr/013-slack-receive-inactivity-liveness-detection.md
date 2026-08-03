# ADR-013: Replace Slack's self-initiated ping/pong-count liveness check with receive-inactivity monitoring

**Date**: 2026-08-02
**Status**: Accepted

Relates to [ADR-006](./006-chat-channel-gateway-architecture.md) (gateway
architecture) and [ADR-012](./012-slack-only-scope-for-websocket-transport-fixes.md)
(scope of the Slack Socket Mode stability fix this ADR is part of).

## Context

Feature `039-slack-socket-mode-stability` fixes the primary defect behind
Slack's 2-minute reconnect loop: the adapter now answers Slack's WebSocket
ping frames with a pong (ADR-012; research.md R-001). Once that fix lands, Slack's own
ping arrives roughly every 10 seconds for as long as the connection is
healthy — a high-frequency liveness signal the adapter gets for free.

Before this change, `SlackAdapter` ran its own liveness check independently
of that signal: `ping_loop` sent a WebSocket ping every 30 seconds and counted
missed pongs, reconnecting after `MAX_MISSED_PONGS` (2) consecutive misses —
up to 120 seconds to detect a dead connection. This mirrors `MessageHandler`'s
own instinct to verify liveness by probing, but with the pong fix in place, it
duplicates a signal that already exists: the receive side goes quiet exactly
when the connection is actually dead, and it does so before a self-initiated
probe would even fire.

## Decision

Replace the self-initiated ping/missed-pong-count mechanism with
**receive-inactivity monitoring**: record the time of the most recently
received frame, of any type, and reconnect once `RECEIVE_TIMEOUT_SECONDS`
(30) seconds pass without one. `ping_loop`, `ping_tick` and `handle_pong` are
removed, along with `PING_INTERVAL_SECONDS` and `MAX_MISSED_PONGS`.

The monitor (`watchdog_loop`) never writes to the connection — it only reads
`@last_received_at` and waits on the same `@connection_ended` queue that a
close frame or socket error already pushes to. It waits for the timeout's
remaining time rather than a fixed poll interval, recomputing that remaining
time whenever a wait ends without a connection-ended notification, since a
frame may have arrived (and pushed the deadline forward) while it was
waiting.

A close frame is now also handled directly (`:close` in `handle_frame`),
which was previously discarded. This gives Slack the same three-layer
disconnect detection Discord already has: a clean close frame is immediate,
a socket-level error is immediate, and only a fully silent link (no close
frame, no error, just nothing) falls through to the 30-second inactivity
timeout.

## Consequences

- Detection of a fully silent connection failure drops from up to 120 seconds
  to 30 seconds, and the close-frame and socket-error paths that were already
  fast stay fast.
- The adapter sends no application-level traffic to keep the connection
  alive; the only socket writes during normal operation are event
  acknowledgements and pong replies, both receive-triggered. This also
  shrinks the surface for the write races addressed by the `@send_mutex`
  serialization introduced in the same feature.
- `SlackAdapter` and `DiscordAdapter` now use different liveness strategies:
  Slack observes Slack-initiated pings, Discord still sends its own
  heartbeats. This is intentional, not an oversight — Discord's protocol has
  no equivalent free signal (its gateway does not ping the client the way
  Slack's Socket Mode does), so there is no analogous inactivity signal to
  observe there instead.
- `RECEIVE_TIMEOUT_SECONDS` is a constant, not a setting. Per the constitution's
  YAGNI principle, no configurability is added until a concrete need for a
  different value appears.

## Alternatives Considered

- **Keep the self-initiated ping alongside the new pong reply**: rejected.
  Once the adapter answers Slack's ping, the adapter would be measuring the
  same liveness twice through two independent mechanisms, doubling the
  constants, state and branches for no gain in detection speed or accuracy
  (constitution III: KISS/YAGNI).
- **Lower `RECEIVE_TIMEOUT_SECONDS` closer to Slack's ~10-second ping
  interval**: rejected. A margin of roughly three ping intervals absorbs
  ordinary network jitter and GC pauses without producing spurious
  reconnects; the spec (FR-004) fixes this at 30 seconds.
- **Poll on a fixed short interval instead of waiting for the computed
  remaining time**: rejected. A fixed interval either adds detection latency
  (if longer than needed) or wakes the thread needlessly often (if short),
  with no benefit over computing the exact remaining time from
  `@last_received_at`.
