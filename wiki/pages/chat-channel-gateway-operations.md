---
title: Chat Channel Gateway Operations
type: component
sources: [S002, S019, S046]
updated: 2026-11-21
---

# Chat Channel Gateway Operations

How the gateway process runs and is set up. Split from [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md).

## Operational model

- It runs as a **separate background process** that connects *outward* to the
  chat service, so **no public URL** is required for the Redmine server (S002).
  Start it with `rake redmine:plugins:ai_helper:chat_channel:gateway` (S002).
  ADR-017 scopes that guarantee to **outbound** adapters — it is not a
  whole-plugin invariant, and enabling an inbound adapter does require a public
  HTTPS URL. Slack/Discord are unaffected (S019). See
  [Public URL Scope for Chat Adapters](./public-url-scope.md).
- Every question is processed under a single Redmine **execution account**
  chosen by the admin; restricting that account's roles restricts what the
  gateway can read and do. Custom commands, agent orchestration, and Langfuse
  tracing all behave identically to web chat (S002).
- **Crash vs. config-error gotcha**: under systemd, `Restart=on-failure`
  restarts crashes (non-zero exit). But configuration errors (invalid tokens,
  no adapter enabled) exit with status **0** and are **not** auto-restarted —
  fix the config and start again (S002).
- **Slack base setup** (feature 028): Socket Mode app with an App-Level Token
  (`xapp-`) and Bot Token (`xoxb-`); base bot scopes `app_mentions:read`,
  `im:history`, `chat:write`, `reactions:write`; events `app_mention`,
  `message.im`; channels are bound to projects in the Chat integrations tab
  (S002). History import adds more scopes — see
  [Chat History APIs](./chat-history-apis.md).

## Processing reaction (removed)

The gateway no longer marks a received message with ⏳ (feature 072's behaviour
was removed in feature 073); `Gateway#enqueue` only queues (S046). History:
[Chat Processing Reaction](./chat-processing-reaction.md).

## Progress message

While a multi-step question runs, `MessageHandler` shows one progress message
that is rewritten and then deleted after the reply, via optional adapter
methods gated by `supports_progress?` (S046). See
[Chat Progress Message](./chat-progress-message.md).

## Related

- [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md) — the main page.
