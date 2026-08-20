---
title: Inline Completion Request Flow
type: component
sources: [S021]
updated: 2026-08-20
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

`cancelPendingRequest()` both increments the request ID **and** aborts, and
`clearSuggestion()` calls it — so disabling, focus loss, acceptance and dismissal
all cancel through a single place, and the duplicate call from `onTextChange` is
harmless because the operation is idempotent (S021).

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
discarded on abort/error and on `dismissSuggestion`, and is never written by
`acceptSuggestion` (S021). See
[Completion Suppression Scope](./completion-suppression-scope.md) for why both
halves of that rule are load-bearing.

Two related client bugs are fixed in the same place: `keyup` and `click` both fed
`onTextChange` without any snapshot comparison, and `scheduleCompletion()`
returned early without clearing an already-scheduled debounce timer — the timer
is now cleared before every early return (S021).

`ai_helper_typo_checker.js` is *not* affected: it is button-triggered and guarded
by `isCheckingTypos` (S021).

## Settings source and validation

Completion settings are read through `ConfigFile.autocompletion_settings` from
`{REDMINE_ROOT}/config/ai_helper/config.yml` — the canonical `ConfigFile`
location. The two ERB overlays
(`app/views/ai_helper/{shared,wiki}/_textarea_overlay.html.erb`) previously did
an inline `YAML.load_file` against a **non-existent in-plugin path**, so
configured values never actually took effect (S021).

Validation happens once at load time, with a warning log per rejected value
(S021):

| Key | Accepted | On absent/invalid |
|-----|----------|-------------------|
| `timeout` | number 1–600 | warn + default `30` |
| `suggestion_color` | `#RGB` / `#RRGGBB` only | rejected |
| `debounce_delay`, `min_length` | non-negative number | `nil` |

`suggestion_color` needs a format check because the ERB interpolates it straight
into a **JS string literal**; making the config path real is what first made that
value injectable (S021). Returning `nil` for `debounce_delay` / `min_length`
preserves the per-view defaults — issue 500 ms, wiki 300 ms, `min_length` 5 —
which intentionally differ and must not change (S021). A corrupt YAML file is
treated as `{}` with a warning so the page still renders (S021).

## Related

- [Completion Request Timeout Policy](./completion-request-timeout-policy.md) ·
  [Completion Suppression Scope](./completion-suppression-scope.md) ·
  [Issue AI Features](./issue-ai-features.md) ·
  [Browser-Side JavaScript Tests](./js-test-convention.md) ·
  [AI Chat Sidebar](./chat-sidebar.md)
