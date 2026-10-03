# ADR-046: Streaming renders are coalesced to at most one per animation frame

**Date**: 2026-10-03
**Status**: Accepted

## Context

Several views stream the LLM response and show it as formatted Markdown while
it is being generated:

- the project health report (`project_health/ai_helper_project_health_actions.js`, SSE via `EventSource`),
- the health report comparison (`project_health/ai_helper_comparison.js`, `EventSource`),
- the "stuff to do" modal (`stuff_todo/ai_helper_stuff_todo.js`, `EventSource`),
- the chat window (`chat/ai_helper.js`, `XMLHttpRequest` through `handleSSEStream`).

Each streamed message carries a small delta, often a single token. On every
message these views appended the delta to the accumulated text and then,
synchronously:

1. re-parsed the **whole** accumulated Markdown with
   `AiHelperMarkdownParser#parse`,
2. replaced the result container with `innerHTML`, discarding and rebuilding
   the entire rendered DOM, and
3. read `scrollHeight` and wrote `scrollTop` to keep the view at the bottom,
   forcing a synchronous layout.

The cost of one render grows with the length of the text, and the number of
renders grows with the number of tokens, so the total work grows roughly
quadratically with the response length. Long health reports made the browser
progressively slower until it stopped responding to input, and it only
recovered once the stream finished.

## Decision

1. A shared helper, `AiHelperFrameRenderer`
   (`assets/javascripts/shared/ai_helper_frame_renderer.js`), coalesces render
   requests. It wraps a render callback and exposes:
   - `schedule()` — request a render on the next animation frame
     (`requestAnimationFrame`); a no-op if one is already pending,
   - `flush()` — run the pending render immediately, if any,
   - `cancel()` — drop the pending render, if any (`cancelAnimationFrame`).

   The render callback takes no arguments and reads the latest accumulated
   text itself when the frame runs.
2. A streaming message handler **never renders directly**. It appends the
   delta to the accumulated text and calls `schedule()`. At most one
   streaming render therefore happens per animation frame, regardless of how
   many messages arrive in that frame.
3. When the stream ends, the pending render is resolved before the final
   state is shown, so a stale streaming render (with the cursor) can never
   overwrite it:
   - views that render the final content themselves (health report,
     comparison, stuff to do) call `cancel()` on completion and on error, then
     render the final content or the error message synchronously;
   - the chat calls `flush()` on completion, because the final message is
     only replaced once `reload_chat` returns from the server and the tail of
     the response must stay visible until then; it calls `cancel()` on a
     network error or a non-200 response.
4. Where a stream can be replaced or abandoned (a new health report
   generation, a new comparison analysis, the stuff-to-do modal being closed
   or reopened), the render callback first checks that its stream is still
   the current one and does nothing otherwise.
5. Any new view that streams a response and re-renders the accumulated
   content must use `AiHelperFrameRenderer` in the same way.

The helper is loaded globally by `ai_helper/shared/_html_header.html.erb`
before the scripts that use it, and also by
`ai_helper/project/health_report_comparison.html.erb`, which already loads
its own copy of the Markdown parser. The script is guarded against double
declaration, and `AiHelperFrameRenderer` is declared as a read-only global in
`eslint.config.js`. With four streaming views sharing the same pattern, it
meets the extraction threshold of ADR-026.

## Consequences

- Streaming render work is bounded by the display refresh rate (normally at
  most 60 renders per second, and close to none while the tab is in the
  background) instead of by the token rate, so long responses no longer
  freeze the browser.
- Each render still re-parses the full accumulated text, so the per-render
  cost still grows with length; the change reduces how often that cost is
  paid, not the cost itself.
- Visible output may lag the network by up to one frame, which is not
  noticeable.
- Tests run in jsdom, where `requestAnimationFrame` is replaced by a manual
  queue (`test/javascript/support/animation_frames.js`); tests flush the queue
  explicitly to assert when renders happen.
- The issue summary, wiki summary, and reply draft streams
  (`chat/ai_helper_streaming.js`) are out of scope. They set `textContent`
  to the accumulated plain text without Markdown parsing, DOM rebuilding, or
  scroll handling, and their output is short, so per-message updates stay
  cheap.

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
  the response is generated.
- **Keep the coalescing logic inline in each view**: rejected. It was first
  written inline in the health report and stuff-to-do views; the same dozen
  lines would then be repeated in four places, which exceeds the ADR-026
  threshold.
