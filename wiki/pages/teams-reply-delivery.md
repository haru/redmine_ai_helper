---
title: Teams Reply Delivery
type: component
sources: [S021, S022, S023]
updated: 2026-08-16
---

# Teams Reply Delivery

Split from [Teams Inbound Chat Adapter](./teams-adapter.md) when that page
outgrew the 600-word limit. It covers the outbound half: how `send_message`
gets an answer back into Teams, and what happens when the post fails. The
adapter's identity, settings and caches stay on the parent page.

## Posting the answer

A client-credentials token from
`https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/token`
(`scope=https://api.botframework.com/.default`) is cached in-process until 60s
before expiry, then the reply is `POST
{serviceUrl}v3/conversations/{conversationId}/activities`. Both `serviceUrl` and
`conversationId` are stored in `reply_metadata` at receipt and read back via
`reply_metadata_for(thread_key:)` — `serviceUrl` varies by tenant and region, and
a channel `thread_key` is not the conversation id (S021). Because a channel
conversation id embeds `;messageid=`, posting to it lands in the question's own
thread; no separate reply API is used (S021).

`MAX_MESSAGE_LENGTH` is 6000 characters — 18KB of Japanese, comfortably inside
the ~28KB activity limit — split paragraph → line → hard cut with
`BaseAdapter#link_safe_cut`, as Discord does. Issue links use a Markdown
`MARKDOWN_LINK_FORMAT` constant defined **inside the adapter**: identical in
effect to `IssueLinkFormatter::DISCORD`, but the shared file is left untouched
until a third copy justifies extracting it (S021).

The token comes from the configured tenant rather than the fixed
`botframework.com` endpoint because the bot is registered as a **single-tenant**
app, whose credentials exist only in its own directory — Microsoft stopped
registering multi-tenant bots on 2025-07-31, so that endpoint is no longer an
option for new integrations (**ADR-019**, Accepted 2026-08-16). The Graph token
of [Teams Graph History](./teams-graph-history.md) comes from the same endpoint;
only the scope differs (S023).

Two nearby designs went down with it. Asking `botframework.com` for the token
regardless of app type fails by construction — a single-tenant app has no
service principal in that directory, which is the very breakage the change
repairs. Trying the tenant endpoint and *falling back* to `botframework.com` was
rejected as worse than either: it hides a configuration error behind a second
request, where a rejected credential has to surface at once (S023).

These Bot Connector calls are the baseline cost of answering; importing context
adds Graph calls on top of them (S022).

## Send failures

| Response | Handling |
|---|---|
| 401 / 403 | config fault — no retry; `fatal_config_error?` returns true |
| 429 | wait per `Retry-After`, up to 3 attempts |
| 5xx | exponential backoff 1s → 2s → 4s, up to 3 attempts |
| 404 / other 4xx | no retry, logged |

The 429 branch is not hypothetical: Teams meters sends **per conversation** —
Microsoft documents roughly 7 requests per second and 60 per 30 seconds — and
returns `Retry-After` when a bot exceeds them, which its guidance says to honour
before backing off exponentially (S021).

Retries are capped at 3 because replies are processed serially by the single
worker, so unbounded retry stalls later questions. Exhausted and non-retryable
cases raise; the gateway's existing `worker_loop` logs and moves to the next
event. Not retrying credential errors matches ADR-006 (S021). Malformed
deliveries need no code either — `parse_events` raises and the controller's
existing rescue logs and returns 200 (S021).

## Related

- [Teams Inbound Chat Adapter](./teams-adapter.md) — the other half: the class,
  its settings, and the caches this delivery path uses.
- [Inbound Reply Metadata](./inbound-reply-metadata.md) — where `serviceUrl` and
  the conversation id are kept, and why they are resolved by event row id.
- [Teams History via Microsoft Graph](./teams-graph-history.md) — the inbound
  counterpart's API calls.
