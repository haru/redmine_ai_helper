---
title: Chat Channel Gateway Architecture
type: component
sources: [S001, S002, S018, S019, S044, S046, S047]
updated: 2026-11-21
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

## Inbound adapters

Feature 044 adds `BaseAdapter.inbound?` in the same declaration style (default
`false`, `true` on `InboundAdapter`). An inbound adapter has no socket: its
`start` polls `ai_helper_inbound_events` for webhook events stored by a Rails
endpoint in Redmine, then `dispatch`es them into the same worker loop, leaving
`Gateway`, `MessageHandler`, `IncomingMessage` and the Slack/Discord adapters
unchanged (S018). ADR-017 records that claim as verified: the whole pre-existing
suite, `gateway_test.rb` and both concrete adapters' tests included, passes
unmodified (S019).

Web search sources: when the answer has sources, `MessageHandler#reply` appends
a plain text list (`- title: url`) under a localized heading after the issue-link
conversion, so titles are never rewritten. The saved answer content does not
contain the list (ADR-052, S044). See
[Web Search & Citations](./web-search-citations.md).

## Operational model

The gateway is a separate outbound-only process under one execution account; the crash vs. config-error restart gotcha and Slack base setup are on [Chat Channel Gateway Operations](./chat-channel-gateway-operations.md) (S002, S019). That page also holds the removed ⏳ reaction and the progress message (S046).

## Related

- [Slack Markdown Block Replies](./slack-markdown-block-replies.md) — how Slack
  posts are sent (markdown blocks) and the shared markdown link format (S047).
- [Chat Context Import](./chat-context-import.md) — how surrounding messages
  are pulled in and fed to the LLM.
- [Chat History APIs](./chat-history-apis.md) — the Slack/Discord retrieval
  details behind the fetch methods.
- [Discord Message Content Intent](./discord-message-content-intent.md) — a
  hard constraint on the Discord adapter's connection.
- [Inbound Chat Webhook Ingest](./inbound-chat-webhook-ingest.md) — the
  decisions behind webhook-push adapters.
- [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md) — the receiving
  controller and its security rules.
- [Inbound Event Queue](./inbound-event-queue.md) — the event table, claiming,
  expiry, retention, and reply metadata.
- [Chat Processing Reaction](./chat-processing-reaction.md) — the removed ⏳
  mark on the question (history).
- [Plugin Overview](./plugin-overview.md) — where the gateway sits among the
  plugin's features.

Design decisions are recorded in ADR-006 (gateway architecture), ADR-007
(Discord connection design) and ADR-017 (inbound webhook gateway, an accepted
amendment to ADR-006's scope) under `docs/adr/` (S001, S019). Full setup guides live in
`docs/slack_gateway_setup.md` and `docs/discord_gateway_setup.md` (S002).
