# ADR-012: Scope the WebSocket transport fixes to the Slack adapter, leaving the same latent defects in Discord

**Date**: 2026-08-02
**Status**: Accepted

Relates to [ADR-006](./006-chat-channel-gateway-architecture.md) (gateway
architecture, per-adapter isolation) and
[ADR-007](./007-discord-adapter-connection-design.md) (Discord connection
design).

## Context

The Slack adapter was reconnecting every two minutes, indefinitely. A live
probe against Socket Mode with real credentials established the cause and
uncovered two further defects in the same code path.

**The primary defect (Slack-specific).** Slack Socket Mode sends a WebSocket
ping frame roughly every 10 seconds and expects a pong in return.
`websocket-client-simple` has no automatic pong reply, and `SlackAdapter#listen`
matched only `:text` and `:pong` in its message handler, so server pings were
discarded. Measured behaviour with no pong reply: Slack pinged at 5.6s, 15.8s,
26.0s and 36.1s, then went silent; the client ping at 30s was answered, the
ones at 60s, 90s and 120s were not. With pong replies the same connection
stayed fully healthy for the entire 125-second probe. Discord is unaffected by
this defect because it uses application-level heartbeats (opcodes 1/11) rather
than WebSocket ping frames.

**Two secondary defects (structurally shared with Discord).** Both adapters
drive `websocket-client-simple` the same way, so both carry them:

1. *Unsynchronized writes to one socket.* The receive thread writes (Slack's
   per-event `acknowledge`, Discord's `send_identify` and heartbeat-on-request)
   while the health-check thread writes pings/heartbeats. The gem's `send`
   performs a bare `@socket.write` with no mutex, so two frames can interleave
   and corrupt the stream.
2. *EOF is never surfaced as a close.* The gem's read loop does
   `unless recv_data = @socket.getc; sleep 1; next; end`, so at EOF it spins
   without ever emitting `:close`. A half-closed connection is only noticed via
   the health-check timeout.

Neither secondary defect has been observed to fire in production. Slack's
2-minute reconnect loop is fully explained by the primary defect alone, and
Discord has been running without incident.

This raises a scope question: fix the two shared defects in both adapters, or
only in Slack?

## Decision

**The fix is scoped to the Slack adapter only.** Feature
`039-slack-socket-mode-stability` changes `slack_adapter.rb` and its tests;
`discord_adapter.rb` is not touched.

The two secondary defects therefore remain latent in the Discord adapter, and
this ADR is the record of that. Concretely, `DiscordAdapter` still:

- writes to its socket from both the receive thread (`send_identify`,
  heartbeat-on-request) and the `heartbeat_loop` thread with no mutex; and
- relies on its heartbeat-ack timeout to notice a half-closed connection,
  because EOF produces no close event.

Discord's exposure to the first is lower than Slack's was: its receive thread
writes only on Hello and on an unsolicited opcode-1, whereas Slack's wrote an
ack for every single event. Its exposure to the second is bounded by the
heartbeat interval Discord announces (~41s), not by a fixed 120s ceiling.

## Consequences

- The change stays small and reviewable, and the Discord integration — which is
  working correctly today — carries no regression risk from this fix. This
  follows the constitution's YAGNI principle: no changes beyond the stated task
  scope.
- The two adapters diverge. After this feature, Slack serializes its writes and
  detects EOF directly; Discord does neither. A maintainer reading both files
  will see the asymmetry, and this ADR is the explanation.
- The latent Discord defects can still fire. The realistic trigger for the
  write race is a burst of gateway traffic coinciding with a heartbeat; the
  symptom would be a rare, hard-to-reproduce disconnect. If that is ever
  observed, this ADR is the starting point, and the Slack implementation is the
  reference to port.
- Deferring means the eventual Discord fix is a second, separate change rather
  than one shared change. If a third adapter is added, the third occurrence is
  the point at which the constitution's DRY rule justifies extracting the
  shared transport handling into `BaseAdapter` — this ADR should be superseded
  then.
- No user-visible behaviour changes for Discord.

## Alternatives Considered

- **Fix both adapters in this feature**: rejected. It doubles the diff and adds
  manual verification against a live Discord guild for defects that have never
  been observed to fire there, in order to harden an integration the user
  reports as stable. The reported problem is Slack-only.
- **Fix both and extract the shared transport handling into `BaseAdapter`**:
  rejected for now. With exactly two occurrences this is the premature
  abstraction the constitution's DRY rule explicitly warns against ("three
  similar occurrences justify extraction"). It also forces the largest possible
  blast radius — a base-class change affecting every adapter — for a bug fix.
- **Replace `websocket-client-simple` with a driver that handles pong replies,
  write locking and close frames itself** (e.g. `websocket-driver`, already in
  the bundle): rejected as out of scope for a bug fix. It would rewrite the
  connection layer of both adapters at once, discarding the reconnect,
  backoff and fatal-error classification behaviour that ADR-006 and ADR-007
  established and that is covered by existing tests. Worth revisiting as
  deliberate work if a third adapter is added.
- **Leave the secondary defects unfixed in Slack too, and only add the pong
  reply**: rejected. The pong fix already rewrites the same message handler and
  health-check loop, so fixing all three together costs little extra, and the
  new receive-timeout detection replaces the client-ping mechanism outright
  rather than sitting alongside it.
