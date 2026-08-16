---
title: Testing an Inbound Chat Adapter
type: howto
sources: [S020, S021, S022]
updated: 2026-08-16
---

# Testing an Inbound Chat Adapter

Split from [Developing an Inbound Chat Adapter](./inbound-adapter-development.md)
when that page passed the 600-word limit. It covers how a webhook adapter is
proved without a live platform: the shared reference-adapter pattern, and the
extra work a signature-verifying adapter needs.

## The reference-adapter pattern

Follow `test/unit/chat_channel/inbound_adapter_test.rb`: a test-only subclass
with toggles for `verify_request`/`parse_events`/`challenge_response`, registered
inside the test file and never under `lib/`, driven through one poll cycle by
stubbing `InboundAdapter.timed_queue_pop` to call `#stop` as a side effect.
That proves integration with the shared `Gateway`/`MessageHandler` path without a
real webhook call or a live platform (S020).

## A verification path you can actually exercise

Teams is the worked example (`test/unit/chat_channel/adapters/teams_adapter_test.rb`,
shoulda + mocha). Two techniques make an inbound adapter testable (S021):

- **Sign your own tokens.** JWT cases — valid, bad signature, `aud` mismatch,
  `iss` mismatch, expired, `serviceUrl` mismatch — are built from an RSA key pair
  generated inside the test, with the JWKS fetch stubbed to hand out that key.
  Nothing depends on a real Microsoft key, so the negative cases are reachable at
  all. One key pair is shared by the suite; RSA generation is slow enough to
  matter per-test.
- **Reset process-level caches in `setup`.** The JWKS cache lives on the adapter
  **class**, not the instance (S022), so it outlives each test's adapter; the
  adapter exposes a cache-reset hook so that tests asserting how often keys are
  fetched start from a known state (S021). Any class-level cache an adapter adds
  needs the same hook.

Only external services are stubbed — `Net::HTTP` via mocha, per Constitution I.
Everything downstream of `parse_events` runs for real. The behaviours worth
covering are the ones with no counterpart in an outbound adapter: request
verification and tenant rejection, which activities count as questions, the
derived `thread_key`/`in_thread`/`event_key`, the session-window rule, reply
splitting and send-failure classes, and history import including its permission
failure (S021).

## Leave the existing suite alone

The Teams feature set a hard condition: `slack_adapter_test.rb`,
`discord_adapter_test.rb`, `inbound_adapter_test.rb`,
`ai_helper_chat_webhook_controller_test.rb`, `gateway_test.rb` and
`message_handler_test.rb` are **not modified by a single line** (S021). That is
the check on the "one adapter class" claim (SC-006/SC-007): if a new platform
forces an edit to the shared tests, the shared code was not general enough — the
edit is the signal, not an inconvenience to work around.

## Related

- [Developing an Inbound Chat Adapter](./inbound-adapter-development.md) — the
  other half: the class, its methods, settings, and the webhook URL.
- [Teams Inbound Chat Adapter](./teams-adapter.md) — the adapter these tests
  cover.
- [Teams Request Verification](./teams-request-verification.md) — what the JWT
  cases assert.
- [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md) — the controller
  behaviour the shared tests already pin down.
