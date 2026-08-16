---
title: Teams Inbound Chat Adapter
type: component
sources: [S021, S022, S023]
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
`adapters/*_adapter.rb` glob plus the `inherited` hook (S021). Proving that a
webhook platform costs one class was itself a goal of the feature (SC-007), the
design target ADR-017 set (S021).

Rejected: a `botframework` Ruby gem — Microsoft publishes no official Ruby SDK
and unofficial ports are unmaintained, while the adapter needs only JWT
verification plus three REST calls, so `Net::HTTP` matches Slack/Discord.
Subclassing `BaseAdapter` directly was also rejected: Teams offers no outbound
persistent connection, so the adapter would re-implement the polling loop (S021).

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
Discord's settings blocks are unchanged, since they declare tokens only (S021).

`tenant_id` carries two jobs: the allowed-organization gate of
[Teams Request Verification](./teams-request-verification.md), and the directory
every access token is requested from — the bot is a single-tenant app
(**ADR-019**), so a wrong tenant also stops replies from being posted (S023).

There is no URL handshake to implement: Bot Framework registers a messaging
endpoint on the Azure Bot resource and never challenges it, so
`challenge_response` keeps the base `nil` (S021).

## The three caches

Nothing cached is persisted, which is what keeps credentials out of the database;
the cost is a few extra calls after a restart. Where each cache lives follows
from **which process reads it** (S022):

| Cache | Held on | Why |
|---|---|---|
| Access tokens, per scope | instance | read only by the resident gateway process, whose adapter lives for the whole run |
| `teamId → aadGroupId`, FIFO-capped at 100 | instance | same — see [Teams History via Microsoft Graph](./teams-graph-history.md) |
| Bot Framework signing keys (JWKS) | **class** | read only by `verify_request` in the web process, which builds a new adapter per delivery |

The class-level exception is not an optimization but a correctness point: an
instance cache in the web process would be re-read every request and its 24-hour
lifetime would never take effect. Sharing it per process is safe because JWKS is
Microsoft's public document — see
[Teams Request Verification](./teams-request-verification.md) (S022).

## Related

- [Teams Reply Delivery](./teams-reply-delivery.md) — the split-off half: posting
  the answer, message splitting, and send-failure handling.
- [Teams Request Verification](./teams-request-verification.md)
- [Teams Activity Mapping](./teams-activity-mapping.md)
- [Teams 1:1 Session Window](./teams-one-to-one-session-window.md)
- [Teams History via Microsoft Graph](./teams-graph-history.md)
- [Developing an Inbound Chat Adapter](./inbound-adapter-development.md)
- [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md)
