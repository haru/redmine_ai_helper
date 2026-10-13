# ADR-054: Progress message for chat channel questions

**Date**: 2026-10-13
**Status**: Proposed (supersedes the processing reaction of ADR-053)

## Context

The web sidebar shows the leader agent's progress (the plan and each step) while it works. The Slack and Discord gateway passed a no-op callback to `Llm#chat`, so a question that takes a while showed nothing but the ⏳ reaction on the question (ADR-053) until the answer arrived. The leader agent sends the progress lines and the streamed answer through the same callback, so a callback cannot tell them apart.

## Decision

- `LeaderAgent` accepts an optional `progress_proc` in its parameters. The "creating plan" line, each step line and the "generating final response" line go to both the existing callback and `progress_proc`, in the same order. The answer's text chunks go only to the callback. What the callback receives does not change.
- `MessageHandler#handle` creates a `ProgressReporter` per question and passes it to `Llm#chat` as `progress_proc`. The first line is posted as one message with an ⏳ reaction; later lines rewrite that message with all lines so far. The reaction is a separate call, so a failed reaction is logged and does not stop the progress message. A question that needs no steps ends after planning, so at most the "creating plan" line is shown; like every progress message it is deleted after the answer has been posted.
- `BaseAdapter` gains `supports_progress?` (false by default), `post_progress`, `mark_progress`, `update_progress`, `delete_progress` and `max_message_length`. An adapter that does not support progress shows nothing. Slack uses `chat.postMessage`, `reactions.add`, `chat.update` and `chat.delete`; Discord uses POST, PUT (the reaction), PATCH and DELETE. Discord progress bodies set `allowed_mentions: { parse: [] }` so a line can never ping anyone.
- `handle` deletes the progress message in an `ensure`, after the answer or the error notice has been posted, so every path (answer, error, guidance) is covered in one place.
- The text is cut to the adapter's limit by dropping the oldest lines first.
- Failures: like ADR-053, the reporter rescues only the errors the adapter lists in `progress_errors` (the chat tool's API errors, unparsable responses and network failures) from the adapter calls and logs them with `ai_helper_logger.error`, so a progress message that cannot be shown never costs the answer. This is a deliberate exception to the no-fallback rule, limited to this auxiliary display and to those transport failures; bugs in building the text or inside the adapter (`NoMethodError`, a `post_progress` that does not return a `Handle`, which raises `TypeError`) are not rescued and surface. The log line names the posted message so a message left behind can be found. After a failed post nothing more is posted, updated, marked or deleted. A failed reaction is only logged. After a failed update the next line tries again, and the final delete is still tried.
- The progress lines are not stored in the Redmine conversation.
- The ⏳ reaction on the question message that ADR-053 added is removed at the maintainer's request: with a progress message on screen it adds no information. A question that never produces a progress message now shows no mark at all. The gateway no longer calls `show_processing` / `clear_processing`, so the adapter hooks, `IncomingMessage#origin_channel_id` and the gateway's reaction error handling are gone. Only the ⏳ on the progress message remains, and it needs the same `reactions:write` / Add Reactions permission.

## Consequences

- Users see the plan and steps in the thread while waiting, and no trace of them afterwards.
- A forced kill of the gateway can leave a progress message behind; there is no sweep.
- The leader agent now has two outputs for progress. Both must be kept in step when a progress line is added.
- Each progress line costs one chat API call, plus one call for the reaction and one to delete the message at the end, on the thread that runs `MessageHandler#handle`.

## Alternatives Considered

- Telling progress from answer chunks by content inside the callback: fragile, and the lines are localized text.
- Giving the callback a type argument: changes the contract of every caller, including the web sidebar.
- Slack's assistant status API: needs the Assistant feature and extra scopes, and has no Discord counterpart.
- Leaving the progress message in place: clutters every thread with text that is stale once the answer is posted.
