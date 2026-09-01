# ADR-021: Snapshot teardown belongs to clearSuggestion, and no-op editor events are ignored

**Date**: 2026-08-21
**Status**: Accepted (refines the mechanism in ADR-019 decision 2)

## Context

ADR-019 settled the rule: a request snapshot suppresses further requests only while the
suggestion it produced is on screen. Its decision 2 put the teardown in a dedicated
`dismissSuggestion()` that Esc and `onBlur` called, next to a `clearSuggestion()` that did not
tear the snapshot down — and named the hazard itself under Consequences: "choosing the wrong
one at a new call site would silently reintroduce regression 1".

Review found the rule broken on three paths that were already in the code:

1. **A response with nothing to display kept its snapshot.** `then` only discarded the snapshot
   through `catch`, so an HTTP 200 carrying `{"suggestion": ""}` left the snapshot recorded with
   nothing on screen. That is exactly what a completion timeout returns by design (ADR-018), so
   every timeout permanently locked completion at that position until the user edited the text.
2. **`clearSuggestion()` was reachable directly.** Unticking the checkbox called it, and so did
   `onTextChange` — which `keyup` and `click` fire even when nothing changed. The suggestion left
   the screen while the snapshot survived, so the debounced request that followed was suppressed.
3. **A `keyup` on a modifier key tore down a perfectly good suggestion**, then paid for an abort
   and a refetch to arrive back where it started.

## Decision

1. **`clearSuggestion()` owns the snapshot teardown; `dismissSuggestion()` is removed.** Taking a
   suggestion off screen and discarding its snapshot are one operation, in one method, on every
   path (Esc, blur, disabling, new input, accepting). The guard inside `forgetRequestSnapshot`
   keeps this correct for accepting, which rewrites the textarea before clearing, and for a
   snapshot that a newer request has already replaced.

2. **A response that displays nothing discards its snapshot**, in `then`, alongside the stale
   branch. "No suggestion is on screen" is what the rule is stated in terms of, and an empty
   answer lands there just as an error does.

3. **`onTextChange` returns early when text and cursor both match the snapshot.** An event that
   changed nothing does not invalidate what is displayed, so the suggestion stays, no teardown
   runs and no request is scheduled. This is what keeps rule 1 from converting harmless `keyup`
   noise into abort/refetch churn.

## Consequences

**Positive**:

- The invariant is structural: there is exactly one way for a suggestion to leave the screen, and
  it takes the snapshot with it. The "two similar methods" hazard ADR-019 recorded is gone.
- A completion timeout no longer disables completion at that position.
- Modifier keys and caret clicks now cost nothing at all — no teardown, no abort, no refetch.

**Negative**:

- `clearSuggestion()` now reads the textarea (`value` / `selectionStart`), so its behaviour
  depends on the caller having already applied any text change. `acceptSuggestion` does; a future
  caller that clears *before* rewriting the text would discard the snapshot it meant to keep.
- The early return in `onTextChange` means the in-flight request is left alone by no-op events.
  That is intended — it is the same request that would be re-issued — but it does mean not every
  `keyup` reaches `cancelPendingRequest` any more.

## Alternatives Considered

- **Keep `dismissSuggestion` and add the missing calls** (rejected): every new `clearSuggestion`
  call site would have to make the same choice correctly, which is the hazard ADR-019 predicted
  and this review found already realised.
- **Only the early return in `onTextChange`** (rejected): it covers the `keyup` / `click` paths
  but leaves the checkbox path and the empty-response path broken.
- **Treat an empty response as a real answer and keep suppressing** (rejected): the user would
  see nothing and have no way to ask again, which is regression 1 under a different name.
- **Document the empty-response case as an exception to ADR-019** (rejected): the exception would
  be the single most common one in production, since it is what every timeout returns.
