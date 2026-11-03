# ADR-071: Comment completion context: note context everywhere, newest-first history, edit scope by earlier comments

**Date**: 2026-11-03
**Status**: Accepted

## Context

- `AiHelperAutoCompletion#buildDefaultRequestBody` sent no `context_type`, and
  the server defaults to `"description"`, so the new-comment field was completed
  with the description prompt: no writer, role or conversation history reached
  the model. Only the Wiki sent `context_type` (through `customRequestData`).
- `IssueReadAgent#build_note_specific_context` assumed the journals were
  already sorted newest first, but `generate_issue_data` takes them from
  `issue.journals` without an order, so `first(20)` and `notes[0..4]` were the
  oldest comments.
- Completing inside an already posted comment must not show the model the
  comment being edited or later comments as "previous" conversation, and the
  writer is the comment's author, not necessarily the current user.

## Decision

- The browser always sends `context_type` (`"description"` for the description,
  `"note"` for the new-comment field and the edit form). The edit form also
  sends `journal_id`.
- `build_note_specific_context` sorts candidates by `[created_on, id]` in
  descending order before taking 20; the prompt keeps the newest 5. `id` breaks
  ties for comments created in the same second.
- With a journal, the writer (name, id, `is_current_user`, role analysis) is
  `journal.user` (an anonymous user when the author was deleted), and only
  comments with a smaller `[created_on, id]` than the edited one are candidates,
  including for the role judgment. Prompt templates are not changed.
- The server validates `journal_id` on `suggest_completion` before any LLM call:
  non-Integer value, missing note context, a journal not visible or not on the
  issue, and a journal the user may not edit are rejected with 400/400/400/403
  and new `ai_helper.completion_errors.*` messages. An omitted or `null`
  `journal_id` keeps the previous behaviour. The resolver checks visibility
  and edit rights for the same user it is given, and logs each rejected request
  with the journal id, issue id and user id.
- A journal without a user raises `ArgumentError` instead of quietly switching
  the writer to the current user.
- `IssueReadAgent#generate_text_completion` builds the context and renders the
  prompt outside any rescue, and `Llm#generate_text_completion` rescues only
  `RubyLLM::Error` and `Faraday::Error` (timeouts are still logged as a warning
  by the agent). A defect in the context code therefore reaches the controller's
  500 response instead of showing as "no suggestion". This applies to every
  context type that uses these two methods, not only comments.

## Consequences

- New-comment completion now sees the writer, role and the newest history
  (a behaviour change chosen by the user).
- The edit-time prompt is consistent with its wording ("previous comments").
- A malformed or foreign `journal_id` produces an error, never a silent fall
  back to new-comment behaviour.

## Alternatives Considered

- Send `customRequestData` from the new-comment initialiser: duplicates
  `buildDefaultRequestBody` in a second place and the edit form needs it too.
- Sort in `IssueJson#generate_issue_data`: changes the output of many other
  callers (summaries, chat tools), beyond this feature.
- A new endpoint for edit-time completion: validation, logging and the LLM call
  are the same; only one value differs.
- Ignore an unknown `journal_id` and treat the request as a new comment: a
  silent fallback that hides errors.
