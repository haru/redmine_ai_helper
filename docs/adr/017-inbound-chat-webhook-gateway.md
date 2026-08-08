# ADR-017: Inbound chat webhook gateway (amends the scope of ADR-006)

**Date**: 2026-08-08
**Status**: Accepted

## Context

ADR-006 established the chat channel gateway architecture around adapters that open an *outgoing* connection to the chat tool (Slack Socket Mode, Discord's Gateway API), so that a Redmine installation never needs a public URL, TLS termination, or a reverse-proxy webhook endpoint (FR-001 of feature 028). That premise does not hold for every chat platform: services such as LINE and Microsoft Teams only deliver events by pushing an HTTPS POST to a URL the integration registers with them. Building on ADR-006 unchanged would leave no way to support these services at all.

Feature 044 adds the receiving side for that class of integration: a single inbound webhook endpoint, a persistent queue table, and an `InboundAdapter` base class that plugs into the existing gateway/adapter-thread machinery. This ADR records the two decisions that extend the scope of ADR-006 rather than duplicate it — see `specs/044-inbound-chat-webhook/research.md` (R-001 through R-010) for the full alternatives analysis behind each one.

## Decision

1. **"No public URL required" is an outbound-adapter property, not a whole-plugin invariant.** ADR-006's decision 1 (outgoing Socket Mode connection) is not revisited or weakened for Slack/Discord: those adapters are completely unaffected by this feature (SC-006/SC-007, proven by the existing adapter test suite passing unmodified). What changes is the scope of the guarantee: an inbound-type adapter, by the nature of the platform it talks to, *does* require a public HTTPS endpoint. Operators who only enable outbound adapters see no new requirement; operators who enable an inbound adapter must expose `/ai_helper/chat_webhook/:channel_type` behind their existing Redmine reverse proxy, the same way they already expose the rest of Redmine.

2. **The webhook endpoint lives in the Redmine web process, not the gateway process.** The receiving HTTP endpoint (`AiHelperChatWebhookController`) runs inside Redmine itself (Puma/Passenger), reusing Redmine's existing public HTTPS URL, TLS termination and reverse-proxy configuration. It only verifies, normalizes and persists an event to `ai_helper_inbound_events` — it never calls the LLM (ADR-006 decision 5's permission separation is preserved: the multi-threaded web process must never touch `User.current`). The resident gateway process remains the only process that runs LLM requests; its `InboundAdapter#start` polls that table (2-second interval) instead of opening a socket, so `Gateway`, `MessageHandler`, `IncomingMessage` and every existing adapter require zero changes (research.md R-001/R-002/R-003).

## Consequences

**Positive**:

- LINE, Teams and any other webhook-only chat platform can now be integrated by writing one `InboundAdapter` subclass (`verify_request`, `parse_events`, optionally `challenge_response`) with no core changes — proven end to end by a test-only reference adapter (FR-012/SC-007).
- Outbound-only deployments (the only kind that existed before this feature) are provably unaffected: the full pre-existing test suite, including `gateway_test.rb` and both concrete adapters' tests, passes unmodified.
- The permission-isolation guarantee from ADR-006 decision 5 is preserved exactly: the web process that is reachable from the internet never runs an LLM request or touches `User.current`.

**Negative**:

- An operator who wants to use an inbound-type integration now needs a public HTTPS URL for their Redmine instance, undoing part of the appeal of ADR-006 decision 1 for that specific integration. This is unavoidable given how those chat platforms work, not a design choice this feature makes.
- The plugin does not implement request-rate limiting on the webhook endpoint; that is delegated to the reverse-proxy layer (documented in `docs/inbound_chat_adapter_development.md`), matching how the rest of Redmine's public surface is protected.

## Alternatives Considered

See `specs/044-inbound-chat-webhook/research.md` for the complete list; the two most relevant to this ADR's scope:

- **HTTP listener inside the resident gateway process** (rejected, R-001): would give the systemd-supervised gateway process its own public-facing surface, splitting "web serving" and "serial LLM processing" across the same process boundary ADR-006 was written to keep separate.
- **Silently reusing ADR-006's "no public URL" framing for every adapter type** (rejected): would misdescribe the actual requirement to operators enabling an inbound adapter and risk them leaving the endpoint unreachable. This ADR exists specifically to make the amended scope explicit rather than leave it implicit in the code.
