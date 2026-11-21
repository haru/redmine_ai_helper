---
title: Inline Completion Request Flow
type: component
sources: [S021, S022, S036, S061]
updated: 2026-11-21
---

# Inline Completion Request Flow

How `AiHelperAutoCompletion`
(`assets/javascripts/ai_helper_auto_completion.js`) issues and cancels
completion requests, and where its settings come from. The feature itself is
described under [Issue AI Features](./issue-ai-features.md); the server-side
timeout rules live in
[Completion Request Timeout Policy](./completion-request-timeout-policy.md).

## Cancellation is at the transport level

Every request is bound to an `AbortController`: before issuing a new one the
existing controller is `abort()`ed, a fresh one is created, and its `signal` is
passed to `fetch` (S021). `catch` returns silently on
`error.name === 'AbortError'` (S021).

`cancelPendingRequest()` increments the request ID, aborts the in-flight request
**and** clears the scheduled debounce timer; `clearSuggestion()` calls it — so
disabling, focus loss, acceptance, Esc and new input all cancel through a single
place (S021). `destroy()` is the one path that does not go through
`clearSuggestion()`: it tears the instance down without clearing the UI, so it
calls `cancelPendingRequest()` itself and removes its listeners using the same
handler references `attachEventListeners()` registered (S021).

The pre-existing request-ID staleness check (`isRequestStale()`) is kept as the
**last line of defense** for a late response that raced the abort (S021).

> The original defect: `cancelPendingRequest()` only bumped the request ID, so
> `isRequestStale()` acted as a post-hoc filter on responses that had already
> consumed a browser connection and a server worker for their full duration
> (S021).

## Suppressing requests that cannot produce anything new

If text **and** cursor position are unchanged since the last request, no request
is issued — including via the manual `Ctrl+Space` trigger, because the
requirement is unconditional and carving out an exception would deviate from the
spec (S021).

The comparison snapshot lives only as long as the suggestion it belongs to: it is
discarded on abort/error, on a response that displays nothing (no candidate, or a
timeout's empty `suggestion`), and in `clearSuggestion()` whenever a displayed
suggestion leaves the screen — and it is never written by `acceptSuggestion`
(S021). Events that change neither text nor cursor (a modifier-key `keyup`, a
click on the caret) return from `onTextChange` before any of that, leaving the
displayed suggestion where it is (S021). See
[Completion Suppression Scope](./completion-suppression-scope.md) for why both
halves of that rule are load-bearing.

Two related client bugs are fixed in the same place: `keyup` and `click` both fed
`onTextChange` without any snapshot comparison, and `scheduleCompletion()`
returned early without clearing an already-scheduled debounce timer — the timer
is now cleared before every early return, and by `cancelPendingRequest()` as well,
because disabling, blur and `destroy()` never reschedule (S021).

`ai_helper_typo_checker.js` is *not* affected: it is button-triggered and guarded
by `isCheckingTypos` (S021).

## Request body and comment edit forms

`buildDefaultRequestBody` always sends `context_type` (`"description"` or
`"note"`); a comment edit form additionally sends `journal_id`. Validation,
context and the per-form lifecycle are on
[Comment Edit Form Aids](./comment-edit-form-aids.md) (S061).

## Settings

Settings come from `ConfigFile.autocompletion_settings` and are validated on every call; the key table, the `suggestion_color` injection guard, defaults and the boot-time YAML behaviour are on [Inline Completion Settings](./inline-completion-settings.md) (S021, S022, S036).

## Related

- [Completion Request Timeout Policy](./completion-request-timeout-policy.md) ·
  [Completion Suppression Scope](./completion-suppression-scope.md) ·
  [Issue AI Features](./issue-ai-features.md) ·
  [Browser-Side JavaScript Tests](./js-test-convention.md) ·
  [AI Chat Sidebar](./chat-sidebar.md)
