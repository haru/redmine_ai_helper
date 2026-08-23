# ADR-019: Completion request suppression lasts only while the suggestion is displayed

**Date**: 2026-08-20
**Status**: Accepted

## Context

Inline auto-completion is driven by `AiHelperAutoCompletion` (`assets/javascripts/ai_helper_auto_completion.js`).
`onTextChange` is bound to `input`, `keyup` and `click`, so reading a paragraph back with the
arrow keys, or clicking inside the textarea, used to issue completion requests for text the
user had not altered by a single character. Those requests were pure waste: same text, same
cursor, therefore the same answer. Combined with the pile-up described in ADR-018, they
multiplied the load that issue #392 reports.

The fix was to record the text and cursor position each request was issued for
(`lastTextSnapshot` / `lastCursorPosition`) and skip a request whose snapshot matches the
current state. That much is uncontroversial. The question this ADR settles is **how long a
recorded snapshot may keep suppressing requests**, because two regressions surfaced in browser
testing when the answer was "until the text changes":

1. **Dismissing killed completion for that position.** The user typed, a suggestion appeared,
   they pressed Esc (or the textarea lost focus). The suggestion was cleared from the overlay,
   but the snapshot survived. Clicking back at the same spot matched the snapshot, so no request
   was issued and no suggestion ever returned. From the user's seat, completion had stopped
   working; only editing the text revived it.

2. **Accepting killed the follow-on completion.** `acceptSuggestion` inserted the suggestion and
   then recorded the resulting text and cursor as a snapshot, specifically so that the `input`,
   `keyup` and `click` events accepting fires would find "nothing changed" and start no request.
   That worked, and it also broke the Copilot-style chain: pressing Tab accepted a suggestion and
   completion went silent, when the whole point of accepting is to keep going.

Both regressions share one root cause: a snapshot was treated as a permanent record of "we
already asked about this state", when what makes suppression correct is much narrower — we
already have that answer, and it is on screen.

## Decision

**A snapshot suppresses a request only while the suggestion it produced is displayed.** Once the
suggestion leaves the screen without being used, the snapshot is discarded and the same text and
cursor position become requestable again.

Concretely:

1. **A request that never produced a usable answer discards its snapshot.** `forgetRequestSnapshot`
   runs in the `fetch` `catch` for aborts and errors alike. It clears the snapshot only when the
   snapshot still describes *that* request, so a newer in-flight request's snapshot is left alone.

2. **Discarding a displayed suggestion discards its snapshot.** `dismissSuggestion()` is the
   single entry point for the two paths where the user turns a suggestion down without taking it —
   Esc in `onKeyDown`, and `onBlur`. It calls `forgetRequestSnapshot` for the current textarea
   state before delegating to `clearSuggestion()`.

3. **Accepting a suggestion records no snapshot.** Accepting rewrites the textarea, so the new
   state cannot match the old snapshot and suppression does not apply to it at all. The
   duplicate `input` / `keyup` / `click` events accepting fires collapse into a single request
   through the existing debounce, which is the mechanism that keeps accepting from firing several
   requests — not the snapshot.

4. **Suppression is not bypassed by the manual trigger.** Ctrl+Space goes through
   `requestSuggestion` like every other path and honours the same check. While a suggestion is on
   screen there is nothing to re-fetch; once it is dismissed, rule 2 has already freed the state.

`null` rather than `''` / `0` marks a discarded snapshot, so a cleared snapshot can never
accidentally match a real textarea state (an empty textarea with the cursor at 0 is a real state).

The behavioural contract is `specs/045-fix-autocompletion-request-pileup/contracts/completion-request-flow.md`
(C-5); the requirements are FR-011 and FR-011a in that feature's `spec.md`.

## Consequences

**Positive**:

- Cursor movement and clicks that change nothing still issue zero requests, which is what
  FR-011 was for and what the request-volume reduction in issue #392 depends on.
- Dismissing a suggestion no longer disables completion for that position, and accepting one
  leads into the next, so both interactions behave the way an editor user expects.
- The rule is stated in terms of something observable — is the suggestion on screen? — instead of
  an internal bookkeeping field, which makes it possible to reason about new call sites.
- All discard paths funnel through `forgetRequestSnapshot`, which owns the "only if it is still
  mine" guard, so a late-arriving failure cannot clear a newer request's snapshot.

**Negative**:

- Accepting a suggestion now costs one LLM request, where the previous implementation cost none.
  This is the intended trade-off: the user asked for the continuation by pressing Tab.
- `clearSuggestion()` and `dismissSuggestion()` look similar and the difference matters, so
  choosing the wrong one at a new call site would silently reintroduce regression 1. The
  distinction is documented at both definitions.
- Suppression now depends on two pieces of state that must stay in agreement (the snapshot and
  whether a suggestion is displayed). Invariant I-4 in that feature's `data-model.md` records the
  relationship.

## Alternatives Considered

- **Keep suppressing after a dismissal** (rejected): this is what shipped first and it is
  regression 1. It reads as "completion is broken" to the user, which is a worse outcome than the
  duplicate request suppression was avoiding.
- **Suppress only while `currentSuggestion` is set, dropping the snapshot entirely** (rejected):
  `currentSuggestion` is null immediately after accepting, so the events accepting fires would
  each start a request. It fixes regression 1 and reintroduces the multi-fire this feature set
  out to remove.
- **A one-shot "skip the next scheduled completion" flag set by `acceptSuggestion`** (rejected):
  accepting fires `input` and then `keyup`, so a single-use flag is consumed by the first and the
  second reschedules. Guarding by state rather than by count is what makes this robust.
- **Let Ctrl+Space bypass suppression** (rejected): it would paper over regression 1 by giving the
  user a manual escape hatch instead of fixing the rule, and `research.md` (R5) had already
  settled that FR-011 applies to every issuing path.
