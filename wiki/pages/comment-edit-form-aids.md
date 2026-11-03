---
title: Comment Edit Form Aids
type: component
sources: [S061]
updated: 2026-11-03
---

# Comment Edit Form Aids

The typo check link and the completion checkbox also appear in the edit form
of a posted comment (feature 085). The mechanism is
[ADR-070](../../docs/adr/070-journal-edit-form-aids-attachment.md); the
completion context is
[ADR-071](../../docs/adr/071-comment-completion-context.md) (S061).

## Rendering and attachment

- The partial `ai_helper/journals/_notes_form_controls.html.erb` is rendered by
  Redmine's `view_journals_notes_form_after_notes` hook, so the UI appears
  whenever the edit form does, even for a user who only has
  `edit_own_issue_notes` and never sees the issue update form. It is gated by
  `PermissionChecker.module_enabled?`, i.e. the module **and** `:view_ai_helper`
  (S061).
- Redmine inserts the form with jQuery after "Edit", so
  `ai_helper_journal_edit_aids.js` observes `#history` with a
  `MutationObserver` and attaches one `AiHelperAutoCompletion` and one
  `AiHelperTypoChecker` per form, keyed by the form element. Registered forms
  whose `isConnected` is false (cancel, save, or removal of `#change-<id>`) are
  released with `destroy()` on both (S061).
- Only the checkbox id contains the journal id; the other elements are found by
  class inside the container. Both classes take optional explicit elements
  (`checkbox`/`container`, `checkButton`/`controlPanel`/`autoCompletion`) that
  replace their id lookups; without them behaviour is unchanged (S061).

## Failure handling

- `attach()` verifies the textarea and the three controls **before creating
  anything** and throws when one is missing — a missing element must never
  reach the page-level fallback, which would bind the form to the new-comment
  checkbox. A `checkbox` option without `container` also throws (S061).
- If the typo checker fails after the completion instance exists, the
  completion instance is destroyed. `scan()` reports a failing form once with
  `console.error` and never retries it, and the observer still releases
  detached forms (S061).
- The typo overlay's 3-second hide timers do nothing once the checker is
  destroyed (S061).

## Request and context

- The browser always sends `context_type` (`"note"` for comments);
  `journal_id` (an Integer) is added for edit forms. The server rejects a
  non-Integer id, a missing note context, a journal that is not visible or not
  on the issue (400) and one the user may not edit (403) before any LLM call;
  each rejection is logged with journal, issue and user id. Visibility and edit
  rights are checked for the same user (S061).
- History is the newest 5 of the newest 20 visible, non-private comments,
  sorted by `[created_on, id]`. While editing, only comments earlier than the
  edited one are candidates (the filter runs before the cap) and the writer is
  the comment's author; a journal without a user raises instead of falling
  back to the current user (S061).
- Context building and prompt rendering run outside any rescue; the agent and
  `Llm#generate_text_completion` rescue only `RubyLLM::Error` and
  `Faraday::Error`, so a defect reaches the controller's 500 instead of
  appearing as "no suggestion". This holds for every context type of those
  methods (S061).

## Related

[Issue AI Features](./issue-ai-features.md) ·
[Inline Completion Request Flow](./inline-completion-request-flow.md) ·
[Completion Request Timeout Policy](./completion-request-timeout-policy.md)
