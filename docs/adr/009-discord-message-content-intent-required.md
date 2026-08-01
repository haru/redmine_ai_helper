# ADR-009: Require the Discord MESSAGE_CONTENT intent in Identify

**Date**: 2026-08-01
**Status**: Accepted

Supersedes decision 7 of [ADR-008](./008-chat-channel-context-import.md)
("Discord's Identify intents stay at 4608") and the intent part of decision 1
of [ADR-007](./007-discord-adapter-connection-design.md) ("Minimal intents, no
privileged MESSAGE_CONTENT").

## Context

ADR-008 kept the Identify intents at `GUILD_MESSAGES + DIRECT_MESSAGES = 4608`
when the context import was added, so that installations which had not enabled
the Message Content Intent in the Developer Portal would keep working: the
gateway would still connect, and only the imported context would be missing.
Turning the toggle on was documented as optional. That rationale rested on
protecting installations that do not exist — the chat channel gateway (028) and
this feature (034) are both unreleased, present only on `develop`.

Exercising the feature showed that the degraded mode is not worth having:

- With the toggle off, Discord returns the surrounding messages with an empty
  body. They are all skipped, the import reports `imported 0 context messages`,
  and no error is raised anywhere — nothing failed.
- The bot then answers as if the discussion did not exist. That is
  indistinguishable, from the outside, from an install that is working
  correctly in a quiet channel, and it is indistinguishable in the log from
  "there genuinely was nothing to import".
- Diagnosing it requires knowing that Discord blanks message bodies, which is
  precisely the knowledge an operator following the setup guide does not have.

The feature's purpose (034) is to make the bot a participant in the thread's
conversation. Without message content it cannot read the thread at all, so the
degraded mode delivers none of the feature's value while looking healthy.

## Decision

The Discord adapter identifies with
`GUILD_MESSAGES (512) + DIRECT_MESSAGES (4096) + MESSAGE_CONTENT (1<<15) = 37376`.

The Message Content Intent is therefore a required setup step, not an optional
one. When it is not enabled for the application, Discord closes the connection
with close code **4014**, which `FATAL_CLOSE_CODES` already classifies as a
fatal configuration error: the adapter stops instead of retrying into the same
broken configuration (ADR-006). Following ADR-006's per-adapter isolation, the
gateway process exits only when Discord is the last live adapter; with Slack
also enabled the process keeps serving Slack and only Discord goes down.

## Consequences

- A missing intent surfaces at connect time as a loud, single, unambiguous
  failure, instead of silently removing context from every later answer. This
  follows the project guideline that errors must surface immediately rather
  than be absorbed by a fallback.
- Discord answering stops entirely when the toggle is off, rather than
  degrading. Nothing is broken for users in the field, because the gateway has
  never been released; the setup guide states the toggle as a required step of
  the initial setup and the troubleshooting section names close code 4014.
- The failure is loud in the log but not always in process state: a
  Slack + Discord install keeps running with Slack alone, so operators who
  watch only for a dead process will miss it. The setup guide calls this out.
- Verified applications need Discord's approval before the intent can be
  enabled, which can delay a deployment.
- Message content also arrives on gateway events now. The adapter does not use
  it there — mention handling already received full content — so no behaviour
  other than the connection requirement changes.

## Alternatives Considered

- **Keep 4608 and document the toggle as required** (the state before this
  ADR): rejected. Documentation cannot prevent the silent-degradation mode; it
  only helps operators who already suspect the intent is the problem.
- **Keep 4608 and warn when an import returns only empty bodies**: rejected. It
  needs a heuristic ("fetched messages but every body was empty") that cannot
  distinguish a genuinely empty channel with certainty, and it reports the
  problem at question time rather than at startup.
- **Request MESSAGE_CONTENT and re-Identify without it on close 4014**:
  rejected. That is exactly the silent fallback the constitution forbids, and
  it restores the degraded mode this ADR exists to remove.
