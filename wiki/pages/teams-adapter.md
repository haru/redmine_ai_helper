---
title: Teams Inbound Chat Adapter
type: component
sources: [S024, S025, S026]
updated: 2026-08-16
---

# Teams Inbound Chat Adapter

Microsoft Teams support (feature 044-teams-chat-adapter) is a **single class**,
`ChatChannel::Adapters::TeamsAdapter < InboundAdapter`, added on the
044-inbound-chat-webhook foundation. It implements only `verify_request`, `parse_events`,
`send_message`, `supports_history?`, `fetch_thread_history`,
`fetch_channel_history`, `issue_link_format` and `fatal_config_error?`; the
polling loop, de-duplication, freshness judgement and retention purge are
inherited unchanged. Load and registration are free — `init.rb`'s existing
`adapters/*_adapter.rb` glob plus the `inherited` hook (S024). Proving that a
webhook platform costs one class was itself a goal of the feature (SC-007), the
design target ADR-017 set (S024).

Rejected: a `botframework` Ruby gem — Microsoft publishes no official Ruby SDK
and unofficial ports are unmaintained, while the adapter needs only JWT
verification plus three REST calls, so `Net::HTTP` matches Slack/Discord.
Subclassing `BaseAdapter` directly was also rejected: Teams offers no outbound
persistent connection, so the adapter would re-implement the polling loop (S024).

## Configuration

`app_token` holds the Microsoft App ID and `bot_token` the client secret — the
credential pair stays at two — and one column, `tenant_id`, is added to
`ai_helper_chat_adapter_settings`, the feature's only migration.
`required_setting_fields` is `[:app_token, :bot_token, :tenant_id]`, so the
existing `required_fields_present_when_enabled` validation covers it. The
settings view renders non-token entries of `required_setting_fields` as plain
text fields through a **generic** block rather than hardcoding `"teams"`; a
tenant id is a directory identifier, not a secret, so it is unmasked, while the
tokens keep the existing masking and `DUMMY_TOKEN` handling. Slack's and
Discord's settings blocks are unchanged, since they declare tokens only (S024).

`tenant_id` carries two jobs: the allowed-organization gate of
[Teams Request Verification](./teams-request-verification.md), and the directory
every access token is requested from — the bot is a single-tenant app
(**ADR-023**), so a wrong tenant also stops replies from being posted (S026).

Single tenant is not a preference but the only shape Azure still issues: since
2025-07-31 the portal's **Type of App** list offers just *Single Tenant* and
*User-Assigned Managed Identity*. Bots registered as multi-tenant earlier keep
working, but this integration does not support them — an operator holding one
registers a new single-tenant bot instead. Carrying an app-type setting was
rejected: it would keep a branch alive for a registration Microsoft no longer
issues, and the adapter had not shipped, so there is no installed base to stay
compatible with. Reach follows from the same fact — the integration serves the
organization it is registered in, and answering from another organization's
Teams means publishing through the Teams Store / AppSource, outside this
plugin's scope (S026).

There is no URL handshake to implement: Bot Framework registers a messaging
endpoint on the Azure Bot resource and never challenges it, so
`challenge_response` keeps the base `nil` (S024).

## The three caches

Nothing cached is persisted, which is what keeps credentials out of the database;
the cost is a few extra calls after a restart. Where each cache lives follows
from **which process reads it** (S025):

| Cache | Held on | Why |
|---|---|---|
| Access tokens, per scope | instance | read only by the resident gateway process, whose adapter lives for the whole run |
| `teamId → aadGroupId`, FIFO-capped at 100 | instance | same — see [Teams History via Microsoft Graph](./teams-graph-history.md) |
| Bot Framework signing keys (JWKS) | **class** | read only by `verify_request` in the web process, which builds a new adapter per delivery |

The class-level exception is not an optimization but a correctness point: an
instance cache in the web process would be re-read every request and its 24-hour
lifetime would never take effect. Sharing it per process is safe because JWKS is
Microsoft's public document — see
[Teams Request Verification](./teams-request-verification.md) (S025).

## Related

- [Teams Reply Delivery](./teams-reply-delivery.md) — the split-off half: posting
  the answer, message splitting, and send-failure handling.
- [Teams Request Verification](./teams-request-verification.md)
- [Teams Activity Mapping](./teams-activity-mapping.md)
- [Teams 1:1 Session Window](./teams-one-to-one-session-window.md)
- [Teams History via Microsoft Graph](./teams-graph-history.md)
- [Developing an Inbound Chat Adapter](./inbound-adapter-development.md)
- [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md)
