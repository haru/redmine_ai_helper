# ADR-022: Microsoft Teams inbound adapter design

**Date**: 2026-08-14
**Status**: Accepted

## Context

ADR-017 established the inbound side of the chat gateway: a shared webhook endpoint in the Redmine web process, a persistent event queue, and an `InboundAdapter` base class whose subclasses only verify, normalize and post. Microsoft Teams is the first real platform built on it, and it raises three questions the shared machinery deliberately leaves to the adapter.

Teams bots are registered as Azure Bot resources. A bot configured as *multi-tenant* — the only configuration that works for the app-package installation flow Teams administrators use — can be installed by any organization, and every one of those organizations sends genuinely signed Bot Framework requests to the registered messaging endpoint. Teams also has no reply threads in one-to-one chats, and its bots receive only the messages addressed to them, not the surrounding discussion the answer often needs.

See `specs/044-teams-chat-adapter/research.md` (R-001 through R-017) for the full alternatives analysis behind each decision.

## Decision

1. **Requests from organizations other than the configured one are refused at reception, not later.** The adapter's `verify_request` compares the activity's `channelData.tenant.id` (falling back to `conversation.tenantId`) with the configured tenant identifier, in addition to the full Bot Framework JWT verification (RS256 against the published JWKS, `iss`, `aud`, `exp`/`nbf` with 300s skew, and the `serviceUrl` claim matched against the body). A mismatch answers 401 and stores nothing, so an unauthorized organization can never reach the queue, let alone an answer. The allowed tenant is a new required setting field (`tenant_id`), which is what makes the check configuration rather than code.

2. **A one-to-one chat conversation is delimited by 24 hours of silence.** Channel conversations are delimited by the Teams thread itself: the conversation id already contains the thread's root message id, so it is used as the `thread_key` unchanged. One-to-one chats have no such structure, so the adapter reads the newest stored event of the same chat and either continues its `thread_key` or mints a new session marker (`<conversation id>#s=<epoch>`) once the previous message is older than 24 hours. The decision is made from `ai_helper_inbound_events` rows by reading only — no writes, no schema change, no new table — so it survives a gateway restart and is fixed at reception time.

3. **Surrounding messages are pulled from Microsoft Graph, not received as pushes.** With the resource-specific consent `ChannelMessage.Read.Group` declared in the Teams app manifest and granted by whoever installs the app in a team, the adapter reads the channel's or thread's messages through Graph when the existing `ContextImporter` asks for them. Retrieval failures raise rather than return an empty history, so the existing `history_unavailable` guidance is what the user sees. One-to-one chats are never queried: they contain nothing but the questions and answers Redmine already stored.

## Consequences

**Positive**:

- The whole integration is one adapter class, one settings column and a settings-form block driven by `required_setting_fields`; the shared endpoint, queue, gateway, `MessageHandler`, `ContextImporter` and the two existing adapters are untouched, which is the goal ADR-017 set out to prove.
- Tenant filtering sits at the same gate as signature verification, so "answer nothing to an organization we do not serve" holds before any LLM work, any queue row, and any log of question content.
- Because the context import is a pull, a missing consent surfaces as a Graph 403 that the user is actually told about, instead of being indistinguishable from a quiet channel.

**Negative**:

- The 24-hour boundary depends on the queue's 7-day retention: once the last event of a chat is purged, the next question starts a new conversation even if it comes sooner. This is the intended failure direction (never wrongly continue an old conversation), but it is a behaviour operators may notice.
- Reading history costs Graph calls on top of the Bot Connector ones, and Microsoft classifies the channel message APIs as protected: some tenants can refuse them even with the consent granted. Answers still go out, without the surrounding context.
- The adapter holds three in-memory caches, never persisted, which keeps credentials out of the database at the cost of a few extra calls after a restart. Two of them (access tokens per scope, and team id → Entra group id capped at 100 entries) belong to the adapter instance, because only the resident gateway process reads them and its adapter lives for the whole run. The third, the Bot Framework signing keys, is held on the adapter *class*: the only thing that reads it is `verify_request`, which runs in the Redmine web process, and that process builds a new adapter for every delivery — an instance-level cache would be re-read on every request and the 24-hour cache lifetime would never take effect. The keys are the public document Microsoft publishes for everyone, so nothing belonging to one integration is shared by holding them per process.

## Alternatives Considered

See `specs/044-teams-chat-adapter/research.md` for the complete list; the ones that most directly shaped the decisions above:

- **Filtering the tenant while generating the answer instead of at reception** (rejected, R-003): would store questions from foreign organizations and answer them with "received", widening the attack surface for no benefit.
- **Using the resource-specific consent push instead of Graph pulls** (rejected, R-012): the bot would receive every channel message, but storing them would need a new table, `parse_events` would gain side effects, messages posted before installation would stay invisible, and a missing consent would be indistinguishable from an empty channel.
- **Tracking the one-to-one session in memory or in `AiHelperChannelConversation`** (rejected, R-007): the first loses the boundary on every gateway restart; the second changes the meaning of a shared table for the existing adapters.
