# ADR-008: Chat channel conversation context import

**Date**: 2026-08-01
**Status**: Accepted

## Context

Feature 028 (ADR-006) made the AI helper reachable from Slack, and feature 030
(ADR-007) added Discord. In both, the only thing the assistant ever sees is the
pair of messages Redmine stores itself: the question addressed to the bot and
the answer it produced. Messages exchanged between humans in the same thread or
channel never reach the LLM.

Feature 034 changes that goal: the assistant is meant to behave as a
*participant in the thread's conversation*, so it must be able to read messages
that were not addressed to it. This forces several decisions:

1. Chat tools expose history through tool-specific APIs with different
   ordering, pagination and permission models, while ADR-006 requires the
   tool-independent core (`MessageHandler`) to stay unchanged when a new
   adapter is added — including an adapter that cannot read history at all.
2. Mentions repeat over the lifetime of a thread. Something must record how far
   a conversation has already imported, and it must survive a gateway restart,
   without ever importing the same message twice into one conversation.
3. Feature 028 deliberately did **not** persist third-party speakers' messages
   on the Redmine side. Feature 034 reverses that so the stored conversation
   explains why an answer was given.
4. Threads can grow without bound, but the prompt sent to the LLM cannot.
5. Discord gates message content behind the privileged MESSAGE_CONTENT intent.
   ADR-007 deliberately identified with the minimal intent set (4608) so that
   no Developer-Portal review is needed; feature 034 needs content the bot was
   not mentioned in.

## Decision

1. **History access is an optional adapter capability, declared explicitly.**
   `BaseAdapter` gains `supports_history?` (default `false`) plus
   `fetch_thread_history` and `fetch_channel_history`, whose default
   implementations raise `NotImplementedError`. The core skips import when the
   capability is absent, so an adapter that cannot read history degrades to
   exactly the pre-034 behaviour and nothing else. A default returning an empty
   array was rejected because it makes "not supported" indistinguishable from
   "no messages found" in behaviour and in the log.

2. **Tool-specific filtering stays in the adapter.** Adapters return
   `HistoryMessage(speaker:, text:)` values in ascending order, with the
   gateway's own messages, messages that mention the bot, system messages
   (joins/leaves) and empty-bodied messages already removed. Messages from
   *other* bots (CI notifications and the like) are kept — they are part of the
   discussion. Only the adapter knows its own bot id, its mention markup and
   its system-message representation.

3. **The import cursor is the message id of the last successfully imported
   mention**, stored in a new
   `ai_helper_channel_conversations.last_imported_message_key` column and
   treated as an opaque, adapter-defined string. Everything up to that mention
   is either already imported or already stored as the question, so fetching
   strictly after it cannot produce a duplicate within the conversation. The
   column is persistent, so restarts change nothing. On a failed import the
   cursor is not advanced, which turns the next mention into a retry over the
   same range. Storing external ids on every imported message and taking their
   maximum was rejected: it would put the comparison of two incompatible id
   schemes (Slack's float `ts`, Discord's snowflake) into the core, where
   Discord's string ordering breaks across digit-length changes.

4. **Imported messages are persisted as conversation messages with the new role
   `"context"`.** They flow to the LLM through the existing
   `AiHelperConversation#messages_for_openai` path, so no parallel handoff
   mechanism exists, and the Redmine conversation history shows the evidence
   behind an answer. This reverses feature 028's "no third-party records on the
   Redmine side" position; the permission model is unchanged, since only the
   chat display name and the message body are stored and speakers are still
   never mapped to Redmine users.

5. **Persistence and LLM handoff are separated.** Every imported message is
   stored; `messages_for_openai` merges consecutive `"context"` messages into a
   single `user` message with an explanatory header and drops the oldest of
   them once their combined length exceeds 20,000 characters. Conversations
   without `"context"` messages — every web-chat conversation — are unaffected.

6. **Thread imports are unbounded; channel and DM imports are capped at 48
   hours and 20 messages.** A thread is one continuous discussion, and a cap
   would silently remove part of it; a channel's top-level messages are only
   loosely related, so a bound limits the damage from unrelated topics. The
   values are fixed constants with no settings screen (KISS/YAGNI).

7. **Discord's Identify intents stay at 4608.** Discord decides message-content
   visibility from the Developer-Portal toggle and applies it to both the
   Gateway and the REST API, so enabling the toggle is enough for REST history
   reads. Requesting a privileged intent that the portal has not enabled closes
   the connection with code 4014, which ADR-007 classifies as fatal — adding
   the bit would stop every existing gateway whose operator has not yet flipped
   the toggle. Operators who do not enable it get empty message bodies, which
   are filtered out as empty, leaving the integration working without context.

8. **A failed history fetch is reported, never hidden.** The error is logged
   with its full message and the answer is prefixed with a notice that the
   context could not be retrieved; the answer itself is still generated and
   posted. This is not the silent fallback the constitution forbids: the
   failure is visible in the log and to the person who asked.

## Consequences

- Adding a chat tool that has no history API still requires only one file under
  `adapters/`; `supports_history?` defaults to false and nothing else changes.
- Slack integrations need four extra scopes (`channels:history`,
  `groups:history`, `mpim:history`, `users:read`) and a reinstall. Discord
  integrations need the Message Content Intent enabled, and verified apps need
  Discord's approval for it. Both are one-time operator actions, documented in
  the setup guides.
- Slack resolves speaker display names through `users.info`, which costs one
  call per previously unseen speaker. A per-adapter FIFO cache (500 entries,
  the same shape as `MAX_REPLY_TARGETS`) keeps repeated mentions in one thread
  free of extra calls.
- Conversations bound to long-lived threads grow indefinitely in the database.
  Only the handoff is bounded; the existing six-month
  `AiHelperConversation.cleanup_old_conversations` remains the only reclamation
  path.
- Third-party chat messages now live in Redmine. They are readable by the
  execution account and by administrators only, and they are rendered as
  escaped plain text (never through `md_to_html`) because they are untrusted
  external input.
- Feature 028's decision not to record third-party speakers is superseded for
  the chat-channel conversation store. ADR-006 itself is left unmodified, as
  ADRs are append-only.

## Alternatives Considered

- **Import only on the first mention in a thread.** Rejected during
  clarification: human discussion normally continues after the bot answers, so
  a first-time-only import cannot make the assistant a participant.
- **Build a context block per turn without persisting it.** Cheaper in storage,
  but it makes the reasoning behind an answer unreconstructible and requires a
  second handoff path alongside the conversation history.
- **Add an `imported` boolean column to `ai_helper_messages` and keep the role
  as `"user"`.** Rejected: the LLM could not tell context from questions, and
  the view would need the extra column anyway to satisfy FR-006.
- **Detect Discord close code 4014 and re-identify without MESSAGE_CONTENT.**
  A fallback path with extra connection states, forbidden by the simplicity
  principle, and unnecessary once the intent is only required in the portal.
- **Expose the window (enabled/period/count) as administrator settings.**
  Deferred until a concrete request exists (YAGNI); the fixed values are
  48 hours and 20 messages.
