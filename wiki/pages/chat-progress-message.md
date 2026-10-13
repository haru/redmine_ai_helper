---
title: Chat Progress Message
type: decision
sources: [S046]
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
  after planning, so at most the "creating plan" line is shown and then
  deleted (S046).
- `ProgressReporter#call` posts the first line, then rewrites the same
  message with all lines; text over `adapter.max_message_length` drops the
  oldest lines first (S046).
- `handle`'s `ensure` calls `finish`, which deletes the message after the
  answer, error notice or guidance, so one place covers every path (S046).
- Progress lines are not stored in the Redmine conversation (S046).

## Adapters

`BaseAdapter#supports_progress?` is false by default. Slack uses
`chat.postMessage` / `chat.update` / `chat.delete` (limit 3900); Discord uses
POST / PATCH / DELETE on the message (limit 1900) with
`allowed_mentions: { parse: [] }` so progress never pings (S046). No new
scopes or permissions are needed (S046).

## Error policy

Like [Chat Processing Reaction](./chat-processing-reaction.md), the reporter
rescues and logs only the adapter's `progress_errors` (API and network
failures) from the three adapter calls; other errors surface. A
progress failure never costs the answer: a failed post stops all further
progress, a failed update is retried on the next line, and delete is still
tried (S046). A deliberate narrow exception to the no-fallback rule.

## Rejected

Telling progress from answer chunks by content, a typed callback, and Slack's
assistant status API (S046). A killed gateway can leave a progress message
behind; there is no sweep (S046).

Related: [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md).
