---
title: Teams 1:1 Session Window
type: decision
sources: [S021, S022]
updated: 2026-08-14
---

# Teams 1:1 Session Window

A Teams 1:1 chat has no threads, so there is no reply-to-the-answer boundary of
the kind Slack and Discord use to end a conversation. Feature
044-teams-chat-adapter cuts conversations by **elapsed time instead: 24 hours**
(S021). Recorded as decision 2 of **ADR-018** (Accepted 2026-08-14) (S022).

The contrast is the point: a *channel* conversation needs no such rule, because
the Teams conversation id already contains the thread's root message id and is
used as `thread_key` unchanged. Only the threadless 1:1 case needs a synthesized
boundary (S022).

## How the boundary is computed

Inside `parse_events`, the adapter reads the single most recent inbound event row
for the same `channel_type`/`channel_id` (S021):

```text
no recent event, or its received_at is older than 24h
  → new session: thread_key = "#{conversation.id}#s=#{received epoch seconds}"
otherwise
  → reuse the recent event's thread_key
```

The decision is made **once, at receipt, in the web process**, and frozen into
`thread_key`. A gateway that processes the event late therefore cannot move the
boundary (S021).

## Why the event table

- It needs no new table and no change to shared components — the whole point of
  SC-007's "one adapter class" claim (S021). The access is **read-only**: the
  judgement writes nothing and changes no schema, which is what keeps it clear
  of the shared queue's lifecycle (S022).
- The evidence lives in the database, so the boundary survives a gateway restart,
  which an in-memory last-message timestamp would not (S021).
- `ai_helper_inbound_events` retains rows for 7 days. If retention removes the
  evidence, the next message simply starts a new conversation — which is exactly
  the desired edge-case behaviour of not silently resuming an ancient exchange
  (S021). ADR-018 books this as a **negative** consequence all the same: the
  24-hour boundary is coupled to a retention window it does not own, so a chat
  quiet for over 7 days restarts sooner than the stated rule implies — the
  intended failure direction, but a behaviour operators may notice (S022).

## Rejected alternatives

- **Read `AiHelperChannelConversation#updated_at`.** That table is a shared
  component, and giving its timestamp the meaning "time of last utterance" is a
  reinterpretation that would reach the existing adapters (S021).
- **A Teams-specific state table.** The same judgement is available from an
  existing table by lookup alone (S021).
- **Keep last-message times in memory.** Lost on gateway restart, so the
  requirement fails (S021).

## Known cost

`ai_helper_inbound_events` has no index on `channel_id`, and the feature
deliberately does **not** add one: with 7-day retention and chat-scale row
counts a scan is harmless, and the alternative is modifying a shared table (S021).

## Related

- [Teams Activity Mapping](./teams-activity-mapping.md) — the other event fields
  computed alongside this one.
- [Inbound Event Queue](./inbound-event-queue.md) — the table read here, and its
  retention window.
- [Teams Inbound Chat Adapter](./teams-adapter.md)
