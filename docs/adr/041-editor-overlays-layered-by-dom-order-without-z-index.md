# ADR-041: Editor overlays are layered by DOM order, without z-index

**Date**: 2026-09-30
**Status**: Accepted

## Context

The plugin layers several elements around Redmine's editor textareas: a
completion overlay (which draws the body text plus the suggestion while the
textarea's own text is transparent), the typo checker overlay, and the typo
checker's control panel. To keep them in the desired paint order, both the
JavaScript and `ai_helper.css` assigned positive `z-index` values (5 to 25)
to the textarea, the overlays, and the panel.

None of the ancestor elements creates a stacking context, so these values
compete page-wide. Redmine's `jsToolBar` appends its toolbar menus (table
generator, code highlight) to the end of `<body>` with no `z-index`
(`z-index: auto`). A positioned element with `z-index: auto` always paints
below any element with a positive `z-index` in the same stacking context, so
those menus opened behind the textarea and the overlays and their items could
not be reached (issue #464).

## Decision

1. Editor elements — the textarea, the completion overlay, the typo overlay,
   and the typo control panel — carry **no `z-index` at all**, neither inline
   (`style.zIndex`) nor via a CSS class. They stay at `z-index: auto`.
2. Paint order inside the editor is expressed through **DOM order**: for
   positioned elements with `z-index: auto`, later siblings paint on top of
   earlier ones. The required order (bottom → top) is:

   | State | Order |
   |-------|-------|
   | Completion, normal | completion overlay → textarea → typo overlay → control panel (last) |
   | Completion, scrollable | textarea → completion overlay → typo overlay → control panel (last) |

   The table assumes the typo overlay is created while the completion
   overlay is in its normal state, which is the case at page load. If the
   typo overlay were created during scrollable mode it would land between
   the textarea and the completion overlay until the completion overlay
   next returns to its normal state.

   The completion overlay is inserted immediately **before** the textarea on
   creation, and moved immediately **after** it only while the scrollable
   suggestion mode is active. The typo overlay keeps its existing position
   (inserted before `textarea.nextSibling`); the control panel keeps its
   existing place at the end of the editor parent.
3. When the completion overlay is moved in the DOM, its scroll position
   resets to 0, so `syncScroll()` runs right after every move, and a move is
   skipped when the overlay already sits in the required position. A
   detached overlay (after `destroy()`) is never moved back into the page.
4. The typo tooltip (`.ai-helper-tooltip`) is an explicit exception and
   keeps `z-index: 10001`. (The `.ai-helper-typo-tooltip` rule also keeps
   its `z-index: 10001` but is not used by any script.)

## Consequences

- Positioned elements appended to `<body>` by Redmine core or other plugins
  (toolbar menus and any other popup) paint above the editor area, because
  the editor elements no longer carry a positive `z-index` page-wide.
- The tooltip now competes page-wide with its `z-index: 10001`. It lives
  inside the typo overlay, which previously had `z-index: 15`/`20` and so
  formed its own stacking context that confined the tooltip. Removing the
  overlay's `z-index` removed that context, and no new one is introduced
  around the editor.
- The completion overlay's scrollable mode relies on DOM reordering plus
  `pointer-events` instead of `zIndex` switching; `syncScroll()` right after
  a move keeps the suggestion aligned with the body text.
- Unit tests (jsdom) cannot compute paint order, so they verify the inputs
  that determine it instead: DOM order, the absence of inline `zIndex`, and
  the absence of `z-index` in the relevant CSS rules. Visual verification is
  manual.
- Any future overlay around an editor must follow the same rule: layer it
  with DOM order, not `z-index`.

## Alternatives Considered

- **Wrap the editor in `isolation: isolate` and keep the inner `z-index`
  values**: rejected. The change would be small, but positive `z-index`
  values would remain inside the editor, and the tooltips' `z-index` would be
  trapped in the same isolated context — parts of a tooltip that extend
  outside the editor area could then paint behind positioned siblings that
  follow the editor in the page.
- **Give Redmine's own menus (`.table-generator`, `.ui-menu`) a `z-index`**:
  rejected. It modifies core assets (out of scope by policy) and would not
  cover any other popup added to the end of `<body>` by core or other
  plugins.
- **Keep the completion overlay after the textarea at all times and raise
  the textarea in front when needed**: rejected. With `z-index` off the
  table there is no way for an earlier positioned sibling to paint on top of
  a later one, so the overlay has to move in the DOM. Leaving the overlay on
  top instead is not an option either: while a suggestion is shown it has an
  opaque background, which would hide the textarea's caret and selection.
- **Keep the overlay before the textarea permanently and only toggle
  `pointer-events`**: rejected. In scrollable mode the overlay must receive
  wheel and scrollbar input, which requires it to paint on top of the
  textarea.
