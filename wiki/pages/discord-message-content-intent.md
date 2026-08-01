---
title: Discord Message Content Intent
type: reference
sources: [S001]
updated: 2026-08-01
---

# Discord Message Content Intent

A durable constraint on the Discord adapter's gateway connection, worth
remembering because getting it wrong breaks *existing* installs (S001).

## The rule

Whether a message's `content` field is populated is governed by the
**Message Content Intent toggle in the Discord Developer Portal**, and that
toggle applies to **both the Gateway and the REST API**. Exceptions always
readable regardless of the toggle: the bot's own messages, DMs, and messages
that mention the bot (S001).

## Why the Identify intents must stay at 4608

The gateway's Identify uses `GUILD_MESSAGES + DIRECT_MESSAGES = 4608` and this
**must not change** (S001):

- Requesting a privileged intent (MESSAGE_CONTENT = `1 << 15`) in Identify when
  it is **not** enabled in the Portal causes gateway **close code 4014** (fatal
  config error) — the gateway of every existing install fails to start.
- REST history retrieval does **not** need the MESSAGE_CONTENT bit in Identify,
  so history import can be added without touching the intents at all.

## Operational consequence

Admins must enable Message Content Intent in the Developer Portal themselves
(and verified apps need separate Discord approval). If they do not, imported
messages arrive with empty bodies, empty-body messages are skipped, and the bot
simply runs "without prior context" — question answering itself still works
(SC-006) (S001).

Rejected alternatives (S001):

- Add MESSAGE_CONTENT to Identify → close 4014 in unconfigured environments;
  breaks existing users.
- Detect 4014 and re-Identify without MESSAGE_CONTENT → a fallback banned by
  constitution III, and adds state transitions.

## Related

- [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md)
- [Chat History APIs](./chat-history-apis.md) — Discord REST history retrieval.

Recorded in ADR-007 (Discord adapter connection design), `docs/adr/` (S001).
