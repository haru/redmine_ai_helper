---
title: Chat Channel Gateway Architecture
type: component
sources: [S001, S002]
updated: 2026-08-01
---

# Chat Channel Gateway Architecture

The chat channel gateway (features 028/030) lets Redmine's AI Helper answer
mentions coming from external chat tools (Slack, Discord). Its code lives under
`lib/redmine_ai_helper/chat_channel/`, split into a **tool-agnostic core** and
per-tool implementations under `adapters/` (S001).

## Structure

- **Core** (tool-independent): `context_importer.rb`, `message_handler.rb`,
  `incoming_message.rb`, `history_message.rb`, `base_adapter.rb`.
- **Adapters** (tool-specific): `adapters/slack_adapter.rb`,
  `adapters/discord_adapter.rb`. Adapters are registered via the same
  `inherited` hook pattern used elsewhere in the plugin (S001).
- Everything a specific tool "knows" — API parameters, mention syntax, system
  message detection, display-name resolution — is confined to `adapters/`, so
  the core keeps working unchanged even if an adapter lacks a capability (S001).

The gateway itself runs as a long-lived rake task; incoming mentions are
turned into an `IncomingMessage` and handled through `MessageHandler` (S001).

## Operational model

- It runs as a **separate background process** that connects *outward* to the
  chat service, so **no public URL** is required for the Redmine server (S002).
  Start it with `rake redmine:plugins:ai_helper:chat_channel:gateway` (S002).
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

## Adapter capability declaration

`BaseAdapter` declares optional capabilities rather than relying on
`respond_to?`, so "unsupported" and "failed" are distinguishable (S001):

```ruby
def supports_history? = false                                   # default: unsupported
def fetch_thread_history(channel_id:, thread_key:, after: nil)  # default: NotImplementedError
def fetch_channel_history(channel_id:, before:, since:, limit:) # default: NotImplementedError
```

An adapter with `supports_history? == false` is a valid normal case — the core
simply proceeds with no prior context. This mirrors 028's
`required_setting_fields` declaration style (S001). Slack and Discord override
these to `true` and implement both fetch methods.

## Related

- [Chat Context Import](./chat-context-import.md) — how surrounding messages
  are pulled in and fed to the LLM.
- [Chat History APIs](./chat-history-apis.md) — the Slack/Discord retrieval
  details behind the fetch methods.
- [Discord Message Content Intent](./discord-message-content-intent.md) — a
  hard constraint on the Discord adapter's connection.
- [Plugin Overview](./plugin-overview.md) — where the gateway sits among the
  plugin's features.

Design decisions are recorded in ADR-006 (gateway architecture) and ADR-007
(Discord connection design) under `docs/adr/` (S001). Full setup guides live in
`docs/slack_gateway_setup.md` and `docs/discord_gateway_setup.md` (S002).
