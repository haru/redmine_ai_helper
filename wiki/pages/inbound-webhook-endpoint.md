---
title: Inbound Webhook Endpoint
type: component
sources: [S018, S019, S020]
updated: 2026-08-08
---

# Inbound Webhook Endpoint

The HTTP half of feature 044: `AiHelperChatWebhookController` at `POST
/ai_helper/chat_webhook/:channel_type`, running inside Redmine's web process.
It verifies, normalizes and stores an event, then answers — it never calls the
LLM (S018, S019). An inbound adapter supplies three methods to it:
`verify_request` and `parse_events`, plus `challenge_response` when the service
needs one (S019). The lifecycle after storage is on
[Inbound Event Queue](./inbound-event-queue.md); the rationale is on
[Inbound Chat Webhook Ingest](./inbound-chat-webhook-ingest.md).

## Anonymous by necessity

The controller copies the pattern `AiHelperMcpController` established:
`skip_before_action :verify_authenticity_token` plus `skip_before_action
:check_if_login_required, raise: false` (S018).

- Skipping `check_if_login_required` is **mandatory**, not cosmetic: with
  `Setting.login_required` on, Redmine returns 403 before any custom auth runs
  — the known Issue #304 problem, which hits webhooks the same way (S018).
- CSRF tokens defend session cookies and don't apply to server-to-server POSTs.
  Authenticity comes from the adapter's `verify_request` instead — a **required
  abstract method with no default implementation** (S018).

## Security rules

- Signature verification needs the **raw request body** (`request.raw_post` /
  `request.body.read`), because the HMAC covers the pre-parse bytes — never
  reconstruct it from the parsed hash (S018).
- Verification failure, unknown channel type and disabled adapter all answer
  404/401 alike, so which adapters are enabled never leaks (S018).
- Tokens and signatures are never logged; raw payloads and speaker identity are
  not persisted (S018).
- Rate limiting is delegated to the reverse proxy — see
  [Public URL Scope](./public-url-scope.md) (S018, S019).
- Target: 95% of webhook responses within 1 second, 100% within 3 (S018).

## The normalized event

`parse_events` returns **exactly** these keys; an event carrying anything else
is logged as an error and skipped, because it cannot be stored (S020):

| Key | Required | Meaning |
|---|---|---|
| `:event_key` | yes | external event id — the dedup key |
| `:text` | yes | question body, mention markup already stripped |
| `:channel_id` | yes | channel or DM identifier |
| `:thread_key` | yes | thread identifier |
| `:message_ts` | no | per-message id, where the platform has one |
| `:dm` | no | direct-message flag (default `false`) |
| `:in_thread` | no | reply-in-thread flag (default `false`) |
| `:reply_metadata` | no | platform data needed to reply; JSON-encoded into the column by `AiHelperInboundEvent#reply_metadata=` |

The bot's own messages are never included, and speaker identity goes into
neither `:text` nor `:reply_metadata` — the plugin records only the configured
service account that answers, as it already does for outbound adapters (S020).

## Failure handling

Errors here favor **not** making the platform retry forever (S020):

- An unparseable request (malformed JSON, unexpected shape) should raise; the
  controller catches it, logs the full backtrace, and still answers `200`.
- A single event that cannot be stored is logged with its backtrace and
  skipped; the other events of that delivery are still stored and the delivery
  still gets its `200`.

## Connectivity checks

`InboundAdapter#challenge_response(request)` returns nil for a normal event, or
a status / content-type / body that is returned verbatim, ending the request.
Challenges are never stored as events (S018).

It is in the base contract from day one because each service differs — Slack's
`url_verification` echoes a `challenge` value, Bot Framework sends an
authenticated empty POST, LINE an empty `events` array — so response-body
generation is adapter-specific knowledge the core must not hold, and a fixed
200 would make some services refuse the URL registration outright (S018). A
non-nil return skips event storage for that request entirely (S020).

## Surfacing the URL

`BaseAdapter.inbound?` (default `false`, `true` on `InboundAdapter`) is a
class-level capability declaration in the style of `supports_history?`; the
settings view (`_channels_tab.html.erb`) shows a webhook URL only for adapters
declaring it, built from `Setting.host_name` / `Setting.protocol` via a named
route helper (S018).

## Related

- [Inbound Event Queue](./inbound-event-queue.md) — the other half: what
  happens to a stored event.
- [Inbound Chat Webhook Ingest](./inbound-chat-webhook-ingest.md) — why the
  endpoint lives in the web process at all.
- [Developing an Inbound Chat Adapter](./inbound-adapter-development.md) — how
  to implement the methods this contract calls.
- [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md)
- [MCP Server Endpoint](./mcp-server-endpoint.md) — the other anonymous
  endpoint, whose pattern this one follows.
