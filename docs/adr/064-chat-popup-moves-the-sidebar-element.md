# ADR-064: Show the chat as a popup by moving the sidebar element

**Date**: 2026-11-01
**Status**: Accepted

## Context

The chat form in Redmine's sidebar is narrow. Feature 083 lets a user switch
the chat to a non-modal popup that can be moved and resized, stays open across
page navigation, and returns to the sidebar when the tab is closed
(`specs/083-chat-form-popup/`). The chat scripts reference IDs such as
`aihelper-chat-conversation` and `ai-helper-message-input` directly
(`assets/javascripts/chat/ai_helper.js`), so the popup must not duplicate them.

## Decision

- **Move, do not clone** (R-001). `#aihelper-sidebar` is moved to
  `document.body` and gets the class `aihelper-popup-mode`
  (`position: fixed`). Closing moves it back to the top of `#sidebar-wrapper`.
  The conversation, the streaming display, the input value, the choice buttons
  and the command completion keep working because the same elements stay alive.
- **Storage split** (R-003). Open state and the unsent draft live in
  `sessionStorage`, so they survive reloads and navigation and are dropped when
  the tab is closed. Position and size live in `localStorage` per user, so they
  survive closing the browser. Keys include the user ID, as the existing fold
  flag does (`aihelper-popup-open_${userId}`, `aihelper-popup-draft_${userId}`,
  `aihelper-popup-layout_${userId}`). MDN documents that a tab opened from
  another page can start with a copy of the opener's `sessionStorage` and that a
  restored tab keeps its session; this is a known limit of "closing Redmine
  means closing the tab".
- **Draft saved on `pagehide`** (R-004). The input value is read once when the
  page is left, because command completion, choice buttons and `form.reset()`
  change it without an `input` event. An input that has not loaded yet leaves
  the previous draft untouched. An empty input removes the draft, so a message
  that was already sent is not carried over.
- **No flash on load** (R-005). An inline script in `_html_header.html.erb`
  reads the open state synchronously and marks `<html>` with
  `aihelper-popup-pending`, which hides `#aihelper-sidebar` until
  `AiHelperChatPopup.init` has moved it.
- **Stacking** (R-006). The popup uses `z-index: 1001`, above Redmine's sticky
  issue header (1000), and drops to 90 while `.ui-widget-overlay` exists, so
  Redmine's modal dialogs (`.ui-front`, 100) stay usable. The plugin's own
  overlays and tooltips use 9998-10001 and stay above both.
- **Pointer Events, no library** (R-007). Move and resize use Pointer Events
  with `setPointerCapture`; the header is the move handle and eight ERB-rendered
  elements are the resize handles. The layout is saved once, on `pointerup`, and only when the pointer moved;
  an axis the user did not change keeps its saved size. `pointercancel` and
  `lostpointercapture` restore the layout from before the drag and save nothing.
- **Default placement** (R-008). The default layout is the measured size of the
  sidebar chat (measured with the foldable area shown, so a folded chat gives
  its expanded height), shifted 24px left and 24px down, with a 240 x 240px
  minimum. It is saved the first time the popup opens so later pages do not
  re-measure; a measurement without a size (0 x 0) is not saved. Layouts that no
  longer fit the viewport are fitted for display and the fitted value is not
  saved.
- **Not offered in the flyout layout** (R-009). Below 900px Redmine moves
  `#sidebar` children into its flyout menu, so the popup icon is hidden by CSS,
  and a popup that is open when the width drops is returned to the sidebar (its
  open state is kept). The breakpoint is `matchMedia('(max-width: 899px)')`.
- **Back/forward cache** (R-010). On `pageshow` with `persisted`, the mode, the
  layout and the draft are re-synchronised from the saved state.
- **Always revealed** (R-005). `aihelper-popup-pending` is removed in a `finally`
  in `AiHelperChatPopup.init` and `AiHelperChat.initSidebar`, so an error never
  leaves the chat hidden; the error itself still surfaces.

## Consequences

- No server change: no DB column, route or controller; only ERB, locale, CSS and
  two new JS files (the pure layout rules and the DOM/state wiring), called from
  two lines in `ai_helper_chat.js`. `jump_to_history` no longer unfolds the
  sidebar chat while the chat is the popup, so the popup never writes the fold
  state.
- Rules that apply only inside Redmine's `#sidebar` (font size, `hr`, `ul`) are
  repeated for `.aihelper-popup-mode` in `ai_helper.css` inside `:where()`, so
  they stay below the plugin's own conversation rules, with the Redmine
  selector named in a comment. Redmine's `@media print { #sidebar { display: none } }`
  is repeated for the popup too. Redmine changes to those rules need the same
  change here.
- A page without the AI Helper sidebar shows no popup, even if the tab's open
  state is saved; the popup returns on the next page that has it.
- With only the AI Helper in the sidebar, an empty sidebar area remains while the
  popup is open (R-011).

## Alternatives Considered

- **`position: fixed` inside `#sidebar-wrapper`** (R-001): Redmine hides the
  wrapper with `#main.collapsedsidebar #sidebar-wrapper { display: none; }`
  (`application.css:377`) when the sidebar is collapsed, so the popup would
  disappear with it.
- **A second chat form for the popup** (R-001): duplicates the element IDs the
  chat scripts rely on.
- **Re-defining a shared look for both places** (R-002): drifts from Redmine's
  own sidebar styles.
- **`localStorage` or the server session for the open state** (R-003): not
  per tab, so a new tab would open as a popup.
- **Saving the draft on every `input` event** (R-004): each programmatic path
  that changes the value would need its own handling.
- **Deciding the open state on the server** (R-005): the server cannot read
  `sessionStorage`.
- **One fixed `z-index`** (R-006): a value above 100 covers Redmine's modal
  dialogs; a value below 1000 hides the close button behind the sticky header,
  so no single value satisfies both.
- **jQuery UI draggable/resizable, or the CSS `resize` property** (R-007): jQuery
  is not allowed in the plugin, and `resize` only offers the bottom-right corner.
- **Measuring the default layout on every page** (R-008): conversation length
  and sidebar width differ per page, so the popup would not stay put.
- **Checking the flyout toggle button's visibility** (R-009): depends on the
  order in which Redmine's `resize` handler runs.
