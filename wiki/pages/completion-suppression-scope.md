---
title: Completion Suppression Scope
type: decision
sources: [S021, S023]
updated: 2026-08-26
---

# Completion Suppression Scope

The "text and cursor unchanged → issue no request" rule holds **only while a
suggestion is actually on screen**. ADR-019 records this scope (FR-011a); the
mechanism it constrains is described in
[Inline Completion Request Flow](./inline-completion-request-flow.md).

## Decision

The snapshot (`lastTextSnapshot` / `lastCursorPosition`) that suppression
compares against is **discarded on three paths** (S021):

1. in `catch` — when the request was aborted or failed;
2. in `then` — when the answer had nothing to display: no candidate, or the empty
   `suggestion` a timeout returns with `200` (ADR-018);
3. in `clearSuggestion` — whenever a displayed suggestion leaves the screen
   without being accepted (Esc, focus loss, disabling, new input).

`acceptSuggestion` deliberately **does not write a snapshot** (S021).

Path 3 was originally a separate `dismissSuggestion()` that only Esc and blur
called, which left the checkbox and `onTextChange` paths clearing the suggestion
while the snapshot survived. ADR-021 folded it into `clearSuggestion` — the one
way a suggestion can leave the screen — so the rule holds by construction (S021, S023).

## Why suppression must not outlive the suggestion

Suppression is only safe while the user still has the candidate in hand. If the
snapshot survived a dismissal, completion would stay suppressed until the user
edited the text — a dismissed suggestion could never be re-requested from the
same position (S021).

The accept path fails the opposite way: writing a snapshot on accept would stop
the *follow-on* completion after a Tab confirmation (spec's US3 scenario 3).
Acceptance is not a suppression case at all — it changes the body text, so the
snapshot no longer matches, and the `input` / `keyup` / `click` events it fires
are coalesced by the debounce into a single request (S021).

## Events that change nothing

`onTextChange` is bound to `keyup` and `click`, which fire for a released
modifier key or a click landing on the caret. Those reach `onTextChange` with the
very state the displayed suggestion was computed for, so it returns early: the
suggestion stays, nothing is torn down and nothing is requested (ADR-021, S021).
Without that, path 3 would turn every such event into a discard plus a refetch of
the identical request.

## Relation to the unconditional rule

Suppression itself remains unconditional as to *how* a request is triggered: the
manual `Ctrl+Space` trigger is suppressed exactly like the debounced path,
because FR-011 does not distinguish trigger paths and carving out an exception
would deviate from the spec (S021). ADR-019 narrows *when* the rule applies (a
suggestion is displayed), not *which trigger* it applies to.

## Related

- [Inline Completion Request Flow](./inline-completion-request-flow.md) ·
  [Completion Request Timeout Policy](./completion-request-timeout-policy.md) ·
  [Issue AI Features](./issue-ai-features.md)
