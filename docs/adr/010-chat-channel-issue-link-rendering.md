# ADR-010: Render issue references as links on the shared gateway send path

**Date**: 2026-08-01
**Status**: Accepted

Extends decision 2 of [ADR-006](./006-chat-channel-gateway-architecture.md)
("Adapter abstraction with automatic registration") by adding one optional
member to the adapter interface. ADR-006 itself remains unchanged.

## Context

Answers delivered through the chat channel gateway mention issues by number,
but the number arrives in Slack and Discord as plain text. A reader has to copy
the number, open Redmine separately and search for it — at least three manual
steps to reach a page the answer already identified (feature 038).

Making those numbers clickable raised four questions that the adapter
abstraction established in ADR-006 did not answer:

1. Where the conversion runs, given that each chat tool has its own link
   syntax and that new adapters must keep working without implementing it.
2. Where the link syntax of a tool is declared.
3. How the conversion interacts with the two existing post-processing steps on
   the same path: the UI control markup removal added in feature 037, and the
   per-adapter splitting of replies that exceed the tool's message length limit.
4. Whether the converted text reaches the stored conversation, which is
   replayed to the LLM as thread context and rendered by Redmine's own chat
   screen.

## Decision

1. **Conversion runs in `MessageHandler#reply`, not in the adapters.**
   `RedmineAiHelper::ChatChannel::IssueLinkFormatter` is applied to the reply
   body immediately before `@adapter.send_message`. That call site is the only
   one in `lib/` and `app/`, so consistent application across every adapter and
   every route (channel, thread, DM) is structural rather than conventional.
   Placing it after the feature-037 markup removal in the same expression fixes
   the ordering of the two steps where it can be read off the code.

2. **Adapters declare their link syntax; they do not implement linking.**
   `BaseAdapter#issue_link_format` returns an `IssueLinkFormatter::Format`
   value object pairing a renderer with the regular expression that matches
   what the renderer produces. `SlackAdapter` returns `SLACK`
   (`<url|#1549>`), `DiscordAdapter` returns `DISCORD` (`[#1549](url)`), and
   the base implementation returns `PLAIN` (`#1549 (url)`). Knowledge of a
   tool's syntax belongs to that tool's adapter, which is where ADR-006 put
   every other tool-specific concern; the linking algorithm stays in one place.

   The `PLAIN` default matters: an adapter that never overrides the method
   still produces a working link, because most chat tools auto-link bare URLs.
   A new integration therefore remains "one subclass in `adapters/`", as
   ADR-006 intended.

   Renderer and pattern are one constant rather than two methods so they
   cannot drift apart — the splitter's correctness depends on the pattern
   matching what the renderer emits.

3. **Link first, split second, and never split inside a link.**
   Linking happens in the handler, splitting inside `send_message`, so the
   order follows from the existing call structure and the length accounting
   already sees the expanded text. `BaseAdapter#link_safe_cut` moves a cut
   position back to the start of any link markup it would otherwise bisect;
   each adapter's `split_text` gains one line. Only the forced
   character-count cut can land inside markup, because the rendered forms
   contain no newline and the other two cut positions are newline offsets.

   The two adapters' otherwise identical `split_text` implementations are left
   duplicated. Consolidating them is a refactor of code this feature does not
   otherwise change, and two occurrences do not meet the project's threshold
   for extraction; only the newly required logic is shared.

4. **Only the outbound text is converted.** The assistant message is persisted
   in `#process_question` before `#reply` runs, so the stored content keeps the
   bare `#1549` form. Tool-specific markup never enters the conversation
   history, is never replayed to the LLM as context, and never appears on
   Redmine's chat screen.

Two supporting choices: absolute URLs come from
`Rails.application.routes.url_helpers.issue_url(id, **Mailer.default_url_options)`,
reusing the path Redmine core already uses for absolute URLs in mail so that
host names carrying a port or a path prefix resolve correctly; and issue
existence and visibility are not checked, because the numbers originate from
Redmine data the LLM just read and the link target enforces permissions on its
own.

## Consequences

**Positive**:

- One audited place produces every string that leaves for a chat tool.
- Adding an adapter costs nothing for this feature, and costs one constant to
  opt into native link syntax.
- The stored conversation stays tool-neutral, so the same history renders
  correctly on Redmine's chat screen and does not teach the LLM to imitate a
  tool's markup.
- Splitting correctness is verified against the same pattern that produced the
  markup, in one shared method rather than per adapter.

**Negative / risks**:

- Whether Discord renders masked links in the `content` of a bot-sent message
  (as opposed to an embed) could not be confirmed from published documentation;
  the open API-docs issue on the topic was closed without an official answer.
  The masked-link form was adopted deliberately, with live verification in
  Discord required before the feature is considered done. If the markup renders
  literally, the fix is to redefine `IssueLinkFormatter::DISCORD` as the plain
  form with the URL wrapped in `<>` to suppress the preview — one constant —
  recorded in a new ADR superseding this one.
- Link markup increases reply length, so long answers split into more messages
  than before.
- Numbers are linked without checking that the issue exists, so an answer that
  invents a number produces a link to a "not found" page.
- The detection is textual: references written as `ID: 1549` are not linked.
  Coverage depends on a prompt instruction that steers gateway answers toward
  the `#1549` form, which is a tendency rather than a guarantee.

## Alternatives Considered

- **Convert inside each adapter's `send_message`.** Rejected: every future
  adapter would have to reimplement the conversion, and an omission would be
  invisible until a user reported unlinked numbers.
- **Convert the answer in `Llm#chat`.** Rejected: that is the shared entry
  point for Redmine's own chat screen, which must keep receiving unmodified
  text.
- **Convert before persisting, in `#process_question`.** Rejected: tool markup
  would enter the conversation history, surface on Redmine's chat screen, and
  be replayed to the LLM as context — the same class of defect feature 037 had
  just fixed for the UI control markup.
- **Keep the link syntax table inside the formatter, keyed by
  `channel_type`.** Rejected: adding an adapter would then require editing an
  unrelated file, contradicting ADR-006's "one subclass" extension model.
- **Declare `render_link` and `link_pattern` as two adapter methods.**
  Rejected: nothing keeps them consistent, and the splitter silently
  mis-cuts if they diverge.
- **Also linkify labelled forms such as `ID: 1549` or `チケット1549`.**
  Rejected: quantities, version numbers and dates would be misread as issue
  numbers. Steering the wording through the prompt keeps detection
  unambiguous.
- **Back a forced cut off to the previous whitespace instead of using the
  pattern.** Rejected: the `PLAIN` form contains a space, so a whitespace
  backoff can still cut a link in half.
- **Use Discord embeds for rich previews.** Rejected: out of scope for
  feature 038, and it would change the shape of every reply, not just the
  issue references in it.
