---
title: Teams History via Microsoft Graph
type: decision
sources: [S024, S025]
updated: 2026-08-14
---

# Teams History via Microsoft Graph

Surrounding-message import for Teams **pulls from Microsoft Graph** rather than
accumulating pushed messages. `supports_history?` is `true` and both fetch
methods are implemented, so the pull-shaped contract already used by Slack and
Discord absorbs Teams with no core change (S024). Recorded as decision 3 of
**ADR-022** (Accepted 2026-08-14) (S025). See
[Chat History APIs](./chat-history-apis.md) for the calls themselves.

## Why pull, not push

Granting the RSC permission `ChannelMessage.Read.Group` also makes Teams **push**
every channel message to the bot, which would need no retrieval API at all. It
was rejected on four counts, the last decisive (S024):

- storing the non-question messages requires a dedicated table, so the feature
  stops being "one adapter class";
- `parse_events` is contractually a pure transformation and would gain a side
  effect;
- messages sent before the bot was installed are unreachable;
- **a missing permission is indistinguishable from "nobody said anything"**, so
  the user could never be told why context is absent.

Pull inverts that last point: Graph answers **403** when the permission is
absent, so the failure is a signal. Import errors are raised, and the existing
`MessageHandler#import_context` catches them and answers anyway with the
`history_unavailable` notice (S024).

Also rejected: the tenant-wide `ChannelMessage.Read.All`, which needs a
one-shot admin consent and contradicts the per-team consent this feature assumes
(S024).

## Consent and scope

RSC is declared in the app manifest under
`authorization.permissions.resourceSpecific` and consented by the **owner or
member of the team the bot was added to** — no organization-wide admin approval.
Scope follows from that: history is reachable only for teams hosting the bot, and
naming any other team's channel simply returns 403, so the restriction is
enforced by Graph rather than by adapter code (S024).

Graph tokens come from
`https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/token` with
`scope=https://graph.microsoft.com/.default`, using the same App ID and secret as
the bot (S024). Speaker display names arrive as `from.user.displayName` in the
response, so no name-resolution call is needed — unlike Slack (S024).

**1:1 chats import nothing** and return `[]`. RSC for personal-scope chats grants
only `ChatMessageReadReceipt.Read.Chat`, and in any case a 1:1 chat contains only
the user's questions and the bot's answers, both already recorded in the Redmine
conversation (S024).

## Resolving `aadGroupId`

Graph addresses a team by its Microsoft Entra group id (a GUID), while activities
carry `channelData.team.id` in `19:…@thread.tacv2` form. The adapter calls
`GET {serviceUrl}v3/teams/{teamId}` (the Bot Connector Teams extension, with the
bot token) and caches `teamId → aadGroupId` in-process, FIFO-capped at 100, the
same shape as the Discord adapter's `@reply_targets`. Reading
`channelData.team.aadGroupId` directly was rejected as the primary path: it is
populated when the app is added to a team but **not guaranteed** on ordinary
message activities, which would fail only intermittently (S024).

## Standing risk

Pulling costs Graph calls **on top of** the Bot Connector calls the reply already
makes — the price of the decision, booked by ADR-022 as a negative consequence
rather than treated as free (S025).

`GET /teams/{id}/channels/{id}/messages` is one of Microsoft's *protected APIs*;
some tenants return 403 despite RSC consent (it has been outside the metered
billing scope since 2025-08-25). The degraded behaviour is the specified one —
still answer, with the notice attached — and the setup guide states the
precondition (S024).

## Related

- [Chat History APIs](./chat-history-apis.md) — Graph parameters next to
  Slack's and Discord's.
- [Chat Context Import](./chat-context-import.md) — what consumes the result.
- [Teams Inbound Chat Adapter](./teams-adapter.md)
