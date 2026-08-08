---
title: Public URL Scope for Chat Adapters
type: decision
sources: [S018, S019]
updated: 2026-08-08
---

# Public URL Scope for Chat Adapters

ADR-006 stated "no public URL required" as a premise of the chat channel
gateway. ADR-017 (Accepted 2026-08-08) amends the **scope** of that guarantee
rather than editing ADR-006, which is append-only: it is an outbound-adapter
property, not a whole-plugin invariant (S018, S019).

## What the guarantee now covers

- **Outbound adapters** (Slack Socket Mode, Discord Gateway) open the
  connection themselves and still need no public URL. ADR-006 decision 1 is
  neither revisited nor weakened for them, and outbound-only deployments —
  every deployment before feature 044 — are provably unaffected: the whole
  pre-existing test suite, `gateway_test.rb` and both adapters' tests included,
  passes unmodified (S019).
- **Inbound adapters** do require a public HTTPS URL, because platforms like
  LINE and Teams deliver events only by POSTing to a URL registered with them.
  Operators expose `/ai_helper/chat_webhook/:channel_type` behind the reverse
  proxy already serving Redmine — no new port, no separate TLS setup (S019).

ADR-017 books the extra requirement explicitly as a **negative** consequence:
unavoidable given how those platforms work, not a choice the feature makes
(S019).

## Rejected: keep the old framing

Silently reusing ADR-006's "no public URL" wording for every adapter type was
rejected. It would misdescribe the requirement to operators enabling an inbound
adapter and risk them leaving the endpoint unreachable — making the amended
scope explicit is the ADR's whole purpose (S019).

## What does not change

ADR-006 decision 5's permission separation survives intact: the
internet-reachable web process never runs an LLM request or touches
`User.current`, and the resident gateway process remains the only one that does
(S019). Rate limiting on the endpoint is delegated to the reverse-proxy layer,
matching how the rest of Redmine's public surface is protected, and documented
in `docs/inbound_chat_adapter_development.md` (S019).

## Related

- [Inbound Chat Webhook Ingest](./inbound-chat-webhook-ingest.md) — the three
  design decisions this scope change enables.
- [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md) — the endpoint the
  public URL points at.
- [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md) —
  the outbound operational model the guarantee originally described.
