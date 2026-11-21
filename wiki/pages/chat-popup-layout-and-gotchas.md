---
title: Chat Popup Layout & Gotchas
type: component
sources: [S058, S063]
updated: 2026-11-21
---

# Chat Popup Layout & Gotchas

Layout rules and gotchas of the chat popup. Split from [Chat Popup](./chat-popup.md).

## Layout
- Move and resize use Pointer Events and `setPointerCapture`: the header moves,
  eight ERB-rendered elements resize. The layout is saved once, on `pointerup`,
  only if the pointer moved; `pointercancel` and `lostpointercapture` restore
  the earlier layout and save nothing (S058).
- Default size is the measured sidebar size, measured with the foldable area
  shown; offset 24px left and 24px down; minimum 240 x 240px. It is saved on the
  first open. A 0 x 0 measurement is not saved. A layout that no longer fits the
  viewport is fitted for display, and the fitted value is not saved (S058).
- `z-index` is 1001 (above Redmine's sticky issue header at 1000) and 90 while
  `.ui-widget-overlay` exists so Redmine's modal dialogs (100) stay usable;
  plugin overlays at 9998-10001 stay on top (S058).

## Gotchas
- `aihelper-popup-pending` on `<html>` hides the chat until init to avoid a
  flash; it is removed in a `finally` so an error never leaves it hidden (S058).
- The popup never changes the sidebar fold state: history jumps skip
  `fold_chat(false)` while in popup mode (S058).
- Rules that only apply inside Redmine's `#sidebar` (font size, `hr`, `ul`, and
  `@media print`) are copied for `.aihelper-popup-mode`, inside `:where()` so the
  plugin's own conversation rules win. Changes to those Redmine rules need the
  same change here (S058).
- With only the AI Helper in the sidebar, an empty sidebar area remains while the
  popup is open (S058).
- A navigation during streaming is left to the existing `reload_chat`, which
  shows the saved conversation (S058).
- The popup's colours come from `var(--oc-*)` with Redmine 6 fallbacks (Redmine 6
  defines no Open Color variables); see
  [Redmine 6 Fallbacks](./redmine-6-open-color-fallbacks.md) (S063).

## Related

- [Chat Popup](./chat-popup.md) — the main page.
