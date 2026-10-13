---
title: Chat Progress Message
type: decision
sources: [S046, S047]
updated: 2026-10-13
---

# Chat Progress Message

Slack and Discord show the leader agent's plan and steps in one message that
is rewritten as work advances and deleted after the answer. Feature 073,
ADR-054 (S046).

## Data flow

- `LeaderAgent` takes an optional `progress_proc`. The "creating plan" line, each step
  line and the "generating final response" line go to the existing callback
  and to `progress_proc`; answer chunks go to the callback only, and what the
  callback receives is unchanged (S046).
- `MessageHandler#handle` builds a `ProgressReporter` per question and passes
  it through `Llm#chat` options. A question that needs no steps ends
  after planning, so at most the "creating plan" line is shown, and it is
  deleted after the answer like every progress message (S046).
- `ProgressReporter#call` posts the first line and adds an ⏳ reaction to it
  (a failed reaction is only logged), then rewrites the same
  message with all lines; text over `adapter.max_message_length` drops the
  oldest lines first (S046).
- `handle`'s `ensure` calls `finish`, which deletes the message after the
  answer, error notice or guidance, so one place covers every path (S046).
- Progress lines are not stored in the Redmine conversation (S046).

## Adapters

`BaseAdapter#supports_progress?` is false by default. Slack uses
`chat.postMessage` / `reactions.add` / `chat.update` / `chat.delete` (limit
3900); Discord uses POST / PUT (the reaction) / PATCH / DELETE (limit 1900) with
`allowed_mentions: { parse: [] }` so progress never pings (S046). The ⏳
reaction needs `reactions:write` / Add Reactions, which the setup guides
already list (S046). An adapter that supports progress also implements
`progress_errors` (see below), and the reporter checks that
`max_message_length` is an Integer of at least 3 (S046).

The ⏳ on the question message (feature 072) was removed: the progress
message now carries the only ⏳, and a question without a progress message
gets none (S046).

## Error policy

Like the removed [Chat Processing Reaction](./chat-processing-reaction.md) hooks, the reporter
rescues and logs only the adapter's `progress_errors` (API errors,
unparsable responses, network failures) from the adapter calls; any
other error, such as a bug inside an adapter, surfaces (S046). A
progress failure never costs the answer: a failed post stops all further
progress, a failed reaction is only logged, a failed update is retried on the
next line, and delete is still tried (S046). A `post_progress` result that is not a `Handle` is a
bug and raises `TypeError`. The log line names the posted message so one left
behind can be found (S046). A deliberate narrow exception to the
no-fallback rule; the rule is in AGENTS.md (CRF-022, SF-010).

## Rejected

Telling progress from answer chunks by content, a typed callback, and Slack's
assistant status API (S046). A killed gateway can leave a progress message
behind; there is no sweep (S046).

Slack progress posts and rewrites are sent as `markdown` blocks with the same text as the
fallback `text`, so the progress list renders as Markdown (S047). The lines are joined with
a single newline; whether a markdown block shows them on separate lines was not checked on a
real workspace (S047). See
[Slack Markdown Block Replies](./slack-markdown-block-replies.md).

Related: [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md).
