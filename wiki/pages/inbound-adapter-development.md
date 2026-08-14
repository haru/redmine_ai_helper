---
title: Developing an Inbound Chat Adapter
type: howto
sources: [S020, S021]
updated: 2026-08-14
---

# Developing an Inbound Chat Adapter

How to support a webhook-push platform (Teams, LINE) on the
044-inbound-chat-webhook foundation. [Teams](./teams-adapter.md) is the worked example — a real adapter
built to this guide (S021). This is the *developer* counterpart to `docs/slack_gateway_setup.md`
/ `docs/discord_gateway_setup.md`, which document *operator* setup for the
outgoing-connection adapters (S020).

Subclass `RedmineAiHelper::ChatChannel::InboundAdapter`, not `BaseAdapter`,
whenever the platform pushes events to a URL you register with it instead of
letting you open a connection. `InboundAdapter` already implements `#start` as
the polling loop over `ai_helper_inbound_events`; you supply only
platform-specific parsing and verification (S020).

## The adapter class

Add `lib/redmine_ai_helper/chat_channel/adapters/<name>_adapter.rb` — the same
location convention as `slack_adapter.rb`/`discord_adapter.rb`, and it is
picked up automatically by the `Dir[…adapters/*_adapter.rb]` glob in `init.rb`,
so there is no manual registration step (S020). Declare `channel_type` and
`required_setting_fields` at class level, then implement:

| Method | Required | Notes |
|---|---|---|
| `verify_request(request)` | yes — no default | HMAC over `request.raw_post`, or a bearer JWT (Teams) |
| `parse_events(request)` | yes | returns the normalized event hashes |
| `challenge_response(request)` | no — defaults to `nil` | only if the platform handshakes |
| `send_message(channel_id:, thread_key:, text:)` | yes | posts the reply via the platform API |

- **`verify_request`** has no default implementation because authenticity for a
  webhook message can only be established by the adapter — there is no Redmine
  session involved. Sign `request.raw_post`, the exact bytes the platform
  signed; a re-serialization of the parsed JSON is not guaranteed byte-identical
  (S020).
- **`parse_events`** returns zero or more hashes in the shape documented on
  [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md); return `[]` when a
  delivery carries nothing to answer, such as a delivery receipt or the bot's
  own message (S020).
- **`reply_metadata_for(thread_key:)`** is worth calling from `send_message`
  only when replying needs more than `channel_id`/`thread_key` — see
  [Inbound Reply Metadata](./inbound-reply-metadata.md) (S020).

## Settings and the webhook URL

No new settings model: `AiHelperChatAdapterSetting` already carries the columns
every adapter shares (`enabled`, `app_token`, `bot_token`, execution account,
default project). Declare the ones you need via `required_setting_fields`,
exactly as an outbound adapter does (S020). Reuse `app_token`/`bot_token` for
whatever credential pair the platform issues — Teams maps them to App ID and
client secret (S021).

A non-credential setting is one column on `AiHelperChatAdapterSetting` named in
`required_setting_fields`: the view renders every declared non-token field as a
plain unmasked text input, adapter-driven rather than keyed on `channel_type`,
and `required_fields_present_when_enabled` covers it for free. Teams'
allowed-tenant id is the first; token-only adapters render as before (S021).

Once enabled under *Administration → AI Helper → Chat integrations*, the
adapter's block shows `https://<Setting.host_name>/ai_helper/chat_webhook/<channel_type>`
to register with the external service. That display is generic — driven by
`inbound?` — so the settings view needs nothing adapter-specific (S020).

## Rate limiting at the proxy

The plugin does not rate-limit the endpoint (see
[Public URL Scope](./public-url-scope.md)); the reverse proxy already fronting
Redmine does. A minimal nginx form is a `limit_req_zone` on
`$binary_remote_addr` (e.g. `rate=20r/s`) applied to
`location /ai_helper/chat_webhook/` with a small burst. Tune it to the traffic
the integration actually expects: per-request work is cheap (verify, normalize,
insert one row), so the limit exists to bound abuse, not to protect throughput
(S020).

## Testing

Follow the reference adapter pattern in
`test/unit/chat_channel/inbound_adapter_test.rb`: a test-only subclass with
toggles for `verify_request`/`parse_events`/`challenge_response`, registered
inside the test file and never under `lib/`, driven through one poll cycle by
stubbing `InboundAdapter.timed_queue_pop` to call `#stop` as a side effect.
That proves integration with the shared `Gateway`/`MessageHandler` path without
a real webhook call or a live platform (S020).

## Related

- [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md) — the event hash
  and what the controller does with what you return.
- [Inbound Event Queue](./inbound-event-queue.md) — the constants and lifecycle
  your `#start` inherits.
- [Inbound Chat Webhook Ingest](./inbound-chat-webhook-ingest.md) — why the
  foundation is shaped this way.
- [Teams Inbound Chat Adapter](./teams-adapter.md) — every method above, filled
  in for a real platform.
