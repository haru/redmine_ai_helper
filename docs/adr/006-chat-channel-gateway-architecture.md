# ADR-006: External chat tool gateway with Socket Mode and a serialized worker

**Date**: 2026-07-19
**Status**: Accepted

## Context

Feature 028 lets users ask the AI Helper questions from external chat tools (Slack first) and receive answers in the same thread, processed under a dedicated Redmine service account (the execution account). Four architectural questions had to be settled:

1. How to receive Slack events when many Redmine installations have no public URL.
2. How to keep the plugin open for future chat tools (Discord, Teams, ...) without touching the core processing each time.
3. Which Redmine permissions gateway questions run under.
4. How to run LLM requests concurrently without corrupting the permission context, given that Redmine's `User.current` is a request-scoped, effectively global mechanism.

## Decision

1. **Gateway process with an outgoing Socket Mode connection.** A resident rake task (`redmine:plugins:ai_helper:chat_channel:gateway`) loads the Rails environment and connects *out* to Slack via Socket Mode (`apps.connections.open` → WebSocket). No public URL, reverse proxy, or webhook endpoint is required. The WebSocket client is `websocket-client-simple` (pure Ruby, one dependency); all Slack Web API calls go through `Net::HTTP` directly. Reconnection is handled in three ways: immediately on Slack's `disconnect` envelopes, with exponential backoff (1s→60s) on socket errors, and on two consecutive missed pongs from a 30-second ping cycle. Authentication failures (`ok: false`) terminate the process without retry — credential problems are never retried into silence.
2. **Adapter abstraction with automatic registration.** `RedmineAiHelper::ChatChannel::BaseAdapter` follows the same `inherited`-hook registration pattern as `BaseAgent`. A new tool integration is one subclass in `chat_channel/adapters/` implementing `channel_type`, `start`, `stop`, `send_message`, and `notify_processing`, plus a `required_setting_fields` declaration. The tool-independent core (`MessageHandler`) resolves the project via `AiHelperChannelBinding` (or the adapter's DM default project), binds threads to `AiHelperConversation` rows via `AiHelperChannelConversation`, and calls the existing `RedmineAiHelper::Llm#chat` entry point so custom commands, Langfuse tracing and agent orchestration work unchanged.
3. **Execution account instead of speaker mapping.** All questions run as one administrator-selected Redmine service account (`AiHelperChatAdapterSetting#redmine_user_id`; only an active user qualifies). The originally planned email-based mapping of Slack speakers to Redmine users was rejected: a Slack profile email is self-asserted, so matching on it lets anyone impersonate a Redmine user by editing their profile. With the execution account, the authorization boundary is Slack itself (who can post in a bound channel or DM the bot), and the administrator narrows what the gateway can do by restricting the account's roles. Speaker identity is not recorded on the Redmine side.
4. **Per-adapter settings in one dedicated model.** `AiHelperChatAdapterSetting` holds one row per `channel_type` (enable flag, `app_token`, `bot_token`, DM default project, execution account), following the `AiHelperModelProfile` pattern of typed shared columns with per-type required-field validation. Adding an adapter adds no columns to `ai_helper_settings` and no new tables.
5. **Single worker thread serializes all LLM processing.** Adapters' receive threads only normalize events into `IncomingMessage` values and enqueue them (`SizedQueue`); one worker thread pops them, wraps each in `connection_pool.with_connection`, sets `User.current` to the execution account, runs the LLM, restores `User.current` in an `ensure`, and posts the reply through the adapter. Concurrent questions therefore cannot interleave permission contexts by construction.

## Consequences

**Positive**:

- Works behind firewalls and on intranet Redmine instances (outgoing HTTPS/WSS only).
- SC-006 holds: the test suite proves a fictional in-memory adapter works end to end with zero changes to `MessageHandler` or the Slack adapter.
- Permission isolation (SC-003) is structural, not conventional: there is exactly one thread that ever touches `User.current`.
- The gateway reuses `Llm#chat`, so behavior matches the web chat (custom commands, tracing, error strings posted back to the thread).

**Negative**:

- Throughput is bounded by the single worker: simultaneous questions queue up and are answered in order. Acceptable for the v1 scale (a handful of concurrent users); revisit only with evidence.
- The gateway is a separate process the operator must supervise (systemd or similar); it is not managed by Puma.
- Slack markdown differences are not translated (answers are posted as-is); a converter can be layered on later if needed.
- No per-speaker attribution on the Redmine side: issues created via the gateway are authored by the execution account, and everyone who can reach the bot shares that account's permissions. Accepted deliberately — auditing individual speakers is delegated to Slack's own logs.

## Alternatives Considered

- **Events API (webhooks)**: rejected — requires a public URL, contradicting FR-001.
- **`slack-ruby-client` gem**: rejected — no first-class Socket Mode support; pulls in a heavy async/EventMachine-era dependency stack for its realtime layer.
- **Email-based speaker mapping** (match the Slack profile email against active Redmine users): rejected — the profile email is self-asserted, making impersonation trivial; per-speaker permissions would rest on an attacker-controlled value.
- **Thread-per-event processing**: rejected — would require proving `User.current` thread-safety under concurrent per-user assignment; a permission leak is the worst possible failure mode for this feature.
- **ActiveJob for LLM work**: rejected — Redmine's default `:async` adapter runs inside the web process, unavailable to the gateway process.
- **Slack columns on `ai_helper_settings`**: rejected during implementation review — each new adapter would keep widening the global settings table; a per-adapter settings model keeps the schema stable.
