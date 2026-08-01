---
title: Discord Message Content Intent
type: reference
sources: [S001, S015]
updated: 2026-08-01
---

# Discord Message Content Intent

A hard requirement of the Discord adapter's gateway connection, worth
remembering because it is what makes the context import work at all (S015).

## The rule

Whether a message's `content` field is populated is governed by the
**Message Content Intent toggle in the Discord Developer Portal**, and that
toggle applies to **both the Gateway and the REST API**. Exceptions always
readable regardless of the toggle: the bot's own messages, DMs, and messages
that mention the bot (S001).

## The Identify intents include MESSAGE_CONTENT

The gateway's Identify uses
`GUILD_MESSAGES + DIRECT_MESSAGES + MESSAGE_CONTENT = 37376` (S015):

- If the toggle is **not** enabled in the Portal, Discord answers Identify with
  gateway **close code 4014**. `FATAL_CLOSE_CODES` already treats 4014 as a
  fatal configuration error, so the adapter logs
  `discord: gateway closed with fatal code 4014` and stops instead of retrying.
  Per ADR-006 the *process* exits only if Discord was the last live adapter; a
  Slack + Discord install keeps serving Slack.
- Requesting the intent is what turns a missing toggle into a startup failure.
  REST history retrieval technically works without the bit in Identify, but
  then it returns empty bodies and the misconfiguration is invisible.

This reverses the earlier design (ADR-008 decision 7), which kept the intents
at `4608` so unconfigured installs would keep running without context — a
rationale that protected installations that do not exist, since the gateway is
unreleased and lives only on `develop` (S015).

## Why the degraded mode was removed

With the toggle off and intents at 4608, nothing failed: Discord returned
empty message bodies, every imported message was skipped as empty, the log
recorded `imported 0 context messages`, and the bot answered as if the
discussion did not exist. That is indistinguishable both from a healthy install
in a quiet channel and, in the log, from "there genuinely was nothing to
import" — while delivering none of the feature's value (S015).

## Operational consequence

Enabling Message Content Intent in the Developer Portal is a required step of
the initial setup, done before the gateway is first started (verified apps need
separate Discord approval). Skip it and Discord answering does not work at all,
rather than working without context (S015).

Rejected alternatives (S015):

- Keep 4608 and document the toggle as required → documentation cannot prevent
  silent degradation.
- Keep 4608 and warn when every imported body is empty → a heuristic that
  cannot be certain, reported at question time rather than startup.
- Request MESSAGE_CONTENT, then re-Identify without it on close 4014 → the
  silent fallback banned by constitution III.

## Related

- [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md)
- [Chat History APIs](./chat-history-apis.md) — Discord REST history retrieval.

Recorded in ADR-009, which supersedes decision 7 of ADR-008 and the intent part
of decision 1 of ADR-007, `docs/adr/` (S015).
