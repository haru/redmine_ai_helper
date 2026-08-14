---
title: Teams Activity Mapping
type: component
sources: [S021]
updated: 2026-08-14
---

# Teams Activity Mapping

How `TeamsAdapter#parse_events` decides a Bot Framework activity is a question,
and what event fields it produces. Verification has already passed at this point
— see [Teams Request Verification](./teams-request-verification.md) (S021).

## What counts as a question

All of the following must hold; otherwise `parse_events` returns `[]`, meaning
200 with nothing stored (S021):

| Condition | Rule |
|---|---|
| Activity type | `type == "message"` — `conversationUpdate`, `messageReaction`, `typing`, `installationUpdate` are out |
| Not the bot itself | `from.id != "28:#{app_id}"` |
| Conversation kind | `conversation.conversationType` is `"channel"` or `"personal"`; `"groupChat"` is out |
| Mention (channels) | some entity with `type == "mention"` and `mentioned.id == recipient.id` |
| Non-empty body | text is not blank after mention removal |

The mention test is mandatory rather than incidental: with the RSC permission
granted (see [Teams History via Microsoft Graph](./teams-graph-history.md)) the
bot receives channel messages that never mentioned it, so only mentions may be
treated as questions — the same rule Microsoft's samples use. Comparing against
`recipient.id` is the documented way to mean "this bot" in a received activity,
and the bot's own user id is derivable as `28:<App ID>`, so unlike Discord the
adapter makes **no** startup API call to learn its own identity. Skipped
`groupChat` and other non-target conversation kinds are logged at info level
(S021).

Mention text is stripped by removing, from `activity.text`, the `text` of each
entity whose `mentioned.id == recipient.id` (e.g. `<at>AI Helper</at>`), then
collapsing runs of whitespace and stripping. Microsoft's guidance is to treat
`entities` as authoritative and never pattern-match the body, which the sender
controls. Mentions of *other* people are kept — they can be part of the question
(S021).

## Event fields

| Field | Team channel | 1:1 chat |
|---|---|---|
| `channel_id` | `channelData.channel.id` (`19:…@thread.tacv2`) | `conversation.id` (`a:1…`) |
| `thread_key` | `conversation.id` (`19:…@thread.tacv2;messageid=<root id>`) | `"#{conversation.id}#s=<session key>"` |
| `message_ts` | `activity.id` | `activity.id` |
| `dm` | `false` | `true` |
| `in_thread` | true when `activity.id` differs from the `messageid=` value | `false` |

- A channel `conversation.id` carries `;messageid=<root>`, identical for every
  message in one thread — so it *is* the "one thread, one conversation" key,
  with no extra derivation (S021).
- Using the **channel** id as `channel_id` is what makes the existing
  `AiHelperChannelBinding` work untouched, and it matches the value an admin
  copies from Teams' "Get link to channel" (S021).
- `in_thread` follows from that: a new top-level post is its own root, so
  `activity.id` equals the `messageid=` value; a reply does not. `ContextImporter`
  switches between thread and channel mode on this flag alone (S021).
- Teams channel message ids are epoch-millisecond strings, so like Discord
  snowflakes they compare **numerically** for newer/older and serve directly as
  the `last_imported_message_key` cursor (S021).
- `event_key` is `"#{conversation.id}:#{activity.id}"`. `activity.id` alone is
  unsafe: epoch-ms ids can collide across conversations, which would make a
  simultaneous question in another conversation look like a redelivery. Prefixing
  the conversation id keeps it unique where Microsoft's own resends repeat it
  (S021).

The 1:1 `thread_key` session key is derived separately — see
[Teams 1:1 Session Window](./teams-one-to-one-session-window.md).

## Related

- [Teams Inbound Chat Adapter](./teams-adapter.md)
- [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md) — the event hash shape.
- [Chat Context Import](./chat-context-import.md) — the consumer of `in_thread`.
