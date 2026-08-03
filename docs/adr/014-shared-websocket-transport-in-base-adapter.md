# ADR-014: Move the shared WebSocket transport handling into `BaseAdapter` and apply it to Discord

**Date**: 2026-08-02
**Status**: Accepted

Supersedes the scope decision of
[ADR-012](./012-slack-only-scope-for-websocket-transport-fixes.md) ("the fix is
scoped to the Slack adapter only"). Extends
[ADR-013](./013-slack-receive-inactivity-liveness-detection.md)
(receive-inactivity liveness detection) to the Discord adapter. Neither of
those ADRs is rewritten; both remain the record of what was decided at the
time.

## Context

ADR-012 knowingly left two latent defects in `DiscordAdapter` — unsynchronized
concurrent writes to one socket, and slow detection of a silently dead
connection — and named the condition under which they should be revisited: "if
a third adapter is added, the third occurrence is the point at which the
constitution's DRY rule justifies extracting the shared transport handling into
`BaseAdapter` — this ADR should be superseded then."

No third adapter was added. Instead the user asked, in feature
`040-discord-transport-fixes`, for the Discord defects to be fixed now and for
the shared parts to be extracted into `BaseAdapter` at the same time.

Comparing the two adapters while planning that work surfaced a third defect,
specific to Discord and not covered by ADR-012: `handle_gateway_message` sent
Identify through `@ws`, but `@ws` is only assigned after
`WebSocket::Client::Simple.connect` returns, while the receive thread starts
inside `connect`. Discord's first frame on a new connection is always Hello, so
a Hello arriving in that window produced an Identify sent to `nil`, which is
silently dropped — and a gateway that never receives Identify closes the
connection. The symptom is an occasional failure to connect right after start
up. Slack had already been given the fix for this shape of problem in feature
039 (the frame's own client is used as the send target), so the divergence
ADR-012 accepted had begun to produce exactly the "fixed on one side only"
asymmetry it predicted.

## Decision

Three decisions are recorded here.

**1. The scope decision of ADR-012 is reversed.** The two latent defects it
documented are fixed in `DiscordAdapter`, together with the third defect above.
Discord's liveness detection is switched to receive-inactivity monitoring on
the terms ADR-013 established for Slack: the bound is the heartbeat interval
Discord announces in Hello multiplied by 1.5 (about 61.9 seconds at the current
41.25-second interval, down from a worst case of about 82 seconds), and the
`@heartbeat_acked` zombie check is deleted. Discord's protocol-mandated
heartbeat is still sent, but it is no longer an input to the liveness
judgement: it runs as the monitor loop's scheduled action, so it does not
introduce a second writing thread.

**2. The shared behaviour is extracted at the second occurrence, not the
third.** The constitution's DRY rule asks for three similar occurrences before
extracting. This extraction happens at two, at the user's explicit direction.
The extracted surface is: frame dispatch with the automatic pong reply
(`handle_frame`), receive-time recording (`touch_received`), the monitor loop
(`watchdog_loop`), serialized sending and closing (`send_frame`,
`close_socket`, `@send_mutex`), connection-end notification
(`request_reconnect`, `connection_ended!`, `socket_errored`, `fatal_error!`),
and the stop flag (`stop`, `stopped?`) and reconnect backoff. Subclasses
override five hooks: `receive_timeout_seconds`, `next_scheduled_action_in`,
`perform_scheduled_action`, `handle_text_frame` and `handle_close_frame`.

The reconnect loop in `start` is deliberately **not** extracted: the concept of
an established connection differs per protocol (Slack's `hello` envelope,
Discord's READY dispatch), and unifying it would only pass branching parameters
around.

**3. The shared code lives in `BaseAdapter`, not in a separate connection
object.** The user chose the parent class. It is also where the existing
`timed_queue_pop` helper — added for exactly this waiting problem in feature
039 — already sits.

## Consequences

- The two adapters no longer diverge on transport. Serialized sending,
  receive-inactivity judgement and disconnect detection exist in exactly one
  place, so a fix to any of them reaches both adapters at once. This removes
  the asymmetry ADR-012 accepted as a cost.
- Discord loses three latent defects: interleaved writes can no longer corrupt
  a frame, a silently dead connection is detected in about 61.9 seconds instead
  of about 82, and Identify is no longer lost when Hello wins the race against
  `@ws` being assigned.
- The shared frame dispatcher classifies the error it catches through the
  existing `fatal_config_error?` hook. A credential error raised while a frame
  is being handled therefore terminates the adapter instead of being retried,
  in both adapters at once — the exact class of divergence this ADR exists to
  end.
- `BaseAdapter` now carries state (`@send_mutex`, `@last_received_at`,
  `@stopped`, `@backoff`) that adapters without a socket never use. That is the
  blast radius ADR-012 wanted to avoid. It is bounded by construction — the
  state is inert unless an adapter calls the transport methods — and the
  in-memory `FakeAdapter` in `base_adapter_test.rb`, which opens no socket,
  passes unchanged as the standing check that this stays true.
- Slack's observable behaviour is unchanged: its method names, log wording and
  constant values are identical, and of the five hooks it implements only
  `handle_text_frame`, which every WebSocket adapter must implement because the
  default raises `NotImplementedError`; the other four keep the shared
  behaviour. The mechanical proof is that
  `test/unit/chat_channel/adapters/slack_adapter_test.rb`
  passes without a single character being edited. The shared log lines are
  built as `"#{channel_type}: ..."`, which reproduces the Slack strings
  exactly.
- The shared monitor loop kept Slack's name, `watchdog_loop`, rather than being
  renamed. A new name would have forced edits to the frozen Slack test file and
  destroyed that proof.
- Discord's close-frame log line changes from
  `"discord: gateway close frame received (code N)"` to
  `"discord: close frame received (code N)"` for non-fatal codes, which now go
  through the shared implementation. Fatal codes (4004/4013/4014) keep their
  own error line and their no-retry classification.
- A third adapter now inherits working transport instead of copying it.

## Alternatives Considered

- **Keep ADR-012's scope and fix only Discord, duplicating Slack's
  implementation**: rejected. It would place the same code in two files and
  recreate the "one side gets fixed, the other does not" failure this feature
  exists to end — the very outcome that let the Identify race be fixed in Slack
  and left standing in Discord.
- **Wait for a third adapter, as ADR-012 proposed**: rejected. The condition
  was a heuristic for when extraction stops being speculative. With two
  concrete implementations already written and their differences fully
  enumerated, the shape of the abstraction is known rather than guessed, and
  the defects are real today.
- **Extract into a separate connection object (composition) rather than the
  parent class**: rejected. It tests slightly more easily without a real
  socket, but connection-end notification, the stop flag and the backoff are
  bound up with each adapter's `start` loop; splitting them out adds two-way
  traffic between adapter and component for no gain. The user chose the parent
  class.
- **Include the transport in a module mixed into both adapters**: rejected.
  Both already inherit from a common parent, so a mixin would add an
  indirection layer that buys nothing.
- **Give Discord a dedicated heartbeat thread and keep the monitor loop
  read-only**: rejected. It would add a second thread writing to the socket,
  which is precisely the defect being fixed.
