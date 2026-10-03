# ADR-046: Streaming renders are coalesced to at most one per animation frame

**Date**: 2026-10-03
**Status**: Accepted

## Context

The project health report and the "stuff to do" modal stream the LLM
response over SSE (`EventSource`). Each SSE message carries a small delta,
often a single token. On every message the handler appended the delta to the
accumulated text and then, synchronously:

1. re-parsed the **whole** accumulated Markdown with
   `AiHelperMarkdownParser#parse`,
2. replaced the result container with `innerHTML`, discarding and rebuilding
   the entire rendered DOM, and
3. read `scrollHeight` and wrote `scrollTop` to keep the view at the bottom,
   forcing a synchronous layout.

The cost of one render grows with the length of the text, and the number of
renders grows with the number of tokens, so the total work grows roughly
quadratically with the report length. Long health reports made the browser
progressively slower until it stopped responding to input, and it only
recovered once the stream finished.

## Decision

1. An SSE message handler **never renders directly**. It appends the delta to
   the accumulated text and schedules a render with `requestAnimationFrame`.
   If a render is already scheduled, nothing new is scheduled; the pending
   render picks up the latest accumulated text when it runs. At most one
   streaming render therefore happens per animation frame, regardless of how
   many messages arrive in that frame.
2. When the stream finishes (`finish_reason === 'stop'`) or errors, the
   pending render is cancelled with `cancelAnimationFrame` before the final
   content or the error message is rendered, so a stale streaming render
   (with the cursor) can never overwrite the final state.
3. A scheduled render checks that its stream is still the current one before
   touching the DOM. A stream replaced by a new generation, or closed by
   closing the modal, does not render into the container afterwards.
4. The final render on completion stays synchronous; only intermediate
   streaming renders are coalesced.

This applies to `project_health/ai_helper_project_health_actions.js` and
`stuff_todo/ai_helper_stuff_todo.js`. Any new streaming view that re-renders
the accumulated content must follow the same pattern.

## Consequences

- Streaming render work is bounded by the display refresh rate (normally at
  most 60 renders per second, and close to none while the tab is in the
  background) instead of by the token rate, so long reports no longer freeze
  the browser.
- Each render still re-parses the full accumulated text, so the per-render
  cost still grows with length; the fix reduces how often that cost is paid,
  not the cost itself.
- Visible output may lag the network by up to one frame, which is not
  noticeable.
- Tests run in jsdom, where `requestAnimationFrame` is replaced by a stub that
  queues callbacks; tests flush the queue explicitly to assert when renders
  happen.
- The chat window (`chat/ai_helper.js`, `handleSSEStream` content callback)
  uses the same per-message full re-parse and is not covered by this change.
  It is a candidate for the same treatment.

## Alternatives Considered

- **Incremental rendering (parse and append only the new delta)**: rejected.
  Markdown constructs such as tables, lists, and code fences change meaning
  as later tokens arrive, so a delta cannot be rendered in isolation without
  a streaming-aware parser. That would be a much larger change to
  `AiHelperMarkdownParser`.
- **Fixed-interval throttling (`setTimeout`, e.g. every 100 ms)**: rejected.
  The interval would be an arbitrary constant, and unlike
  `requestAnimationFrame` it keeps rendering while the tab is hidden.
- **Show raw text during streaming and parse only once at the end**:
  rejected. It would remove the formatted live preview that users see while
  the report is generated.
