# ADR-053: Processing reaction lifecycle owned by the gateway

**Date**: 2026-10-13
**Status**: Proposed

## Context

ADR-006 listed `notify_processing` as an adapter method. PR #358 removed the processing reaction (⏳) from both the Slack and Discord adapters because it was added at receive time and never reliably removed, so hourglasses stayed on messages. Users now get no immediate sign that the bot received their question.

## Decision

- `BaseAdapter` has two hooks, `show_processing(message:)` and `clear_processing(message:)`, which do nothing by default. Slack (`reactions.add` / `reactions.remove`, `hourglass_flowing_sand`) and Discord (`PUT` / `DELETE .../reactions/%E2%8F%B3/@me`) implement them. This replaces the `notify_processing` method named in ADR-006.
- `Gateway#enqueue` calls `show_processing` right before queueing, after the shutdown check, so a message dropped at shutdown never gets a mark. The flag is checked again after the call, because the API call can take seconds; if shutdown was requested meanwhile, the message is not queued and its mark is cleared at once (otherwise it would be queued behind the shutdown marker, never processed, and keep its mark).
- `Gateway#worker_loop` calls `clear_processing` in an `ensure` around each message, so success, error replies, guidance replies and exceptions all remove the mark. Shutdown has no extra clean-up: the existing drain processes every queued message, each clearing its own mark.
- Gateway rescues every exception from either hook and logs it with `ai_helper_logger.error` (adapter type, thread key, full message), then carries on, so a missing permission or a deleted message never costs the answer. Adapters hide only expected states: Slack `already_reacted` / `no_reaction`. Discord hides nothing: its documentation defines a 204 response for both `PUT` and `DELETE` and no error for an existing or missing reaction, and code 10014 (Unknown Emoji) means a malformed emoji, so it is raised like any other error.
- `IncomingMessage#origin_channel_id` identifies the channel the message itself lives in. It defaults to `channel_id`; only a Discord mention inside an existing thread passes the thread id. No mutable channel map is kept.

## Consequences

- The mark appears at receive time and disappears after the answer. A forced kill of the gateway can leave a mark behind; there is no start-up sweep.
- A failing reaction call is visible in the log but does not stop processing. This is a deliberate exception to the no-fallback rule, limited to this auxiliary display.
- Adapters call the chat API synchronously on their receive thread.

## Alternatives Considered

- Putting show/clear in `MessageHandler#handle`: the mark would appear only when the worker starts, not on receipt, and the direct (no gateway) path would behave differently.
- A start-up sweep of leftover marks: needs history scans and extra permissions, for a rare case.
- Letting hook errors propagate: one failed reaction would drop the answer.
