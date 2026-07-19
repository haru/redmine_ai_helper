# ADR-007: Discord adapter connection design

**Date**: 2026-07-19
**Status**: Accepted

## Context

Feature 030 adds Discord as the second chat integration on top of the
abstraction layer built in feature 028 (ADR-006): a `ChatChannel::BaseAdapter`
subclass, the shared tool-independent `MessageHandler`, and a resident gateway
process. Discord differs from Slack in ways that force several connection- and
conversation-level decisions:

1. Discord has no Socket-Mode equivalent that hands out a per-connection URL
   with a separate app-level token; a bot connects to the Gateway with one bot
   token and must run its own heartbeat/identify handshake.
2. Reading arbitrary message content now requires the **privileged
   MESSAGE_CONTENT intent**, which needs extra Developer-Portal setup (and
   review for large bots).
3. Discord has first-class **threads** and **replies**, so "same conversation"
   can be expressed in more than one way.
4. Discord's Gateway supports session **Resume**, an optional but non-trivial
   protocol for replaying missed events after a disconnect.
5. FR-014 requires Slack and Discord to run in one gateway process so that one
   integration's failure does not stop the other — the single-adapter crash
   behavior from ADR-006 is no longer acceptable.

## Decision

1. **Minimal intents, no privileged MESSAGE_CONTENT.** The Identify payload
   requests `GUILD_MESSAGES (512) + DIRECT_MESSAGES (4096) = 4608` only.
   Discord still delivers the full `content` of messages that mention the bot
   and of direct messages even without MESSAGE_CONTENT, which is exactly the
   set this integration reacts to (bot mentions and DMs). Messages that do not
   mention the bot arrive with empty `content` and are naturally ignored. This
   keeps the operator's setup simple (SC-004) and is the least-privilege
   configuration.

2. **Re-Identify on every reconnect; no Resume.** All three reconnect triggers
   — Reconnect/Invalid Session opcodes, socket errors (exponential backoff
   1s→60s), and missed heartbeat acks (zombie-connection detection) — open a
   fresh connection and send a new Identify. Resume (tracking
   `resume_gateway_url`, `session_id` and the sequence number, plus Opcode 6
   and event replay) is deliberately not implemented. Its only benefit is
   avoiding a session-start-limit charge (default 1,000/day), and realistic
   disconnect rates stay far below that. Missed messages during a disconnect
   are already an accepted edge case. Authentication/configuration failures
   (REST 401, close codes 4004/4013/4014) raise `DiscordApiError` and terminate
   without retry, matching ADR-006's "credential problems are never retried".

3. **Conversation identity via a `thread_key` with three modes.** The
   `thread_key` both identifies the conversation and tells `send_message` where
   to post, with no new database entity (028's constraint):
   - **Thread mode** (guild, new mention in a normal channel): a thread is
     created from the question message. Because a message-created thread's id
     equals the message id, `thread_key = "{parent_channel_id}:{thread_id}"` is
     decided at receive time with no extra state.
   - **Thread continuation** (mention inside an existing thread):
     `GET /channels/{id}` resolves the thread's `parent_id`, so bindings match
     on the parent channel and `thread_key = "{parent_id}:{thread_id}"`.
   - **Reply mode** (DMs, and channels where a thread cannot be created):
     replies are posted as Discord replies (`message_reference`).
     `thread_key = "{channel_id}:msg:{root_message_id}"`. In DMs the
     conversation continues when a user replies to one of the bot's answers,
     the root found by walking the reply chain back to its origin with
     `GET /channels/{id}/messages/{id}`; a reply to a non-bot message, or a
     referenced message that cannot be fetched, starts a new conversation. In
     guild reply mode, replying with `message_reference` is only the answer's
     posting format (per FR-013/FR-007, spec.md:254-255) — it is not a
     continuation mechanism, since `process_guild_message` does not inspect
     `message_reference`; every mention in these channels starts a new
     conversation.

4. **Gateway fault isolation instead of single-adapter-crash-stops-all.** The
   gateway now keeps running while any adapter thread is alive: a crashed
   adapter is logged (distinguishing configuration/credential errors) but not
   restarted, and the gateway shuts down only when the last adapter exits. When
   all adapters have died, it raises `ConfigurationError` if every death was a
   configuration/credential error (exit 0, no supervisor retry) or the first
   genuine runtime error otherwise (supervisor retries). A graceful shutdown
   (SIGTERM/SIGINT) never reports past adapter deaths as an error. With a single
   adapter the behavior is identical to ADR-006 (crash = zero adapters =
   shutdown), so the change is backward compatible.

## Consequences

**Positive**:

- Operator setup needs no privileged intents and no public URL (outgoing WSS
  only), consistent with the Slack integration.
- Reply-chain resolution is stateless, so DM conversations survive a gateway
  restart without persisting any mapping.
- Slack and Discord run in one process; a bad Discord token no longer takes
  Slack down (FR-014). SC-006 holds: `MessageHandler`, `IncomingMessage`,
  `BaseAdapter` and the Slack adapter are unchanged.
- No new gem, table, or migration; the adapter is one file auto-loaded and
  auto-registered by the existing `inherited` hook.

**Negative**:

- Continuation in reply mode costs one REST call per chain hop to walk to the
  root. This is negligible against LLM latency (SC-002) but is more traffic
  than a stored mapping would need.
- Without Resume, events published during a disconnect are lost (accepted edge
  case), and frequent reconnects consume session-start budget.
- Reacting in a newly created thread requires remembering the message's real
  channel in an in-memory map, which is process-local (rebuilt on restart, in
  lockstep with the also-lost in-flight queue, so no inconsistency).

## Alternatives Considered

- **Use the MESSAGE_CONTENT privileged intent**: rejected — unnecessary for a
  mention/DM-only bot and it complicates operator setup.
- **`discordrb` gem**: rejected — a large library with its own event loop and
  many dependencies, disproportionate to a single low-traffic connection (same
  reasoning that rejected `slack-ruby-client` in ADR-006).
- **Implement Gateway Resume**: rejected — significant protocol and test
  complexity for a benefit (avoiding session-start-limit consumption) that does
  not matter at this scale; re-Identify is simpler and sufficient.
- **Persist a message-id → conversation map for DM continuation**: rejected —
  would add a new entity, violating 028's "no new entities" design; stateless
  reply-chain walking is restart-safe and needs no schema.
- **Keep the single-adapter-crash-stops-all gateway**: rejected — directly
  contradicts FR-014; one integration's credential problem must not stop the
  other.
