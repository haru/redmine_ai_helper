---
title: Redmine 6 Fallbacks for Open Color Variables
type: decision
sources: [S063]
updated: 2026-11-21
---

# Redmine 6 Fallbacks for Open Color Variables

Feature 087 / ADR-072 (issue #570): why the popup background and the reply
"Apply" button lost their colours on Redmine 6, and the rule that stops it
recurring. Related: [Chat Popup](./chat-popup.md),
[Chat Popup Design Decisions](./chat-popup-design-decisions.md).

## Cause
- Redmine 7 defines `--oc-*` (Open Color) on `:root`; Redmine 6.0 and 6.1 define
  none (S063).
- Nine declarations in `assets/stylesheets/ai_helper.css` used `var(--oc-*)` with
  no fallback. In Redmine 6 a declaration with an undefined variable is invalid at
  computed-value time: the property becomes `unset` (transparent background, no
  border, no shadow; `color` inherits) and the earlier declaration is not
  used (S063).

## Rule
- Every `var(--oc-*)` in a plugin stylesheet gets a non-empty fallback:
  `var(--oc-gray-0, #f9fafb)`. Redmine 7 ignores it, so its colours are unchanged;
  Redmine 6 uses it (S063).
- The fallback is Redmine 6's value for the same element and state, from the same
  selector in Redmine 6's `application.css`. If Redmine 6 has no counterpart,
  decide with the maintainer; never fill in another version's or Open Color's
  value (S063).
- Two declarations had no counterpart: the Apply button's `:active` background
  (uses the hover value `#ddd`) and the popup shadow on 6.0 (no sticky issue
  header; 6.1's value is used) (S063).
- A comma inside a fallback is part of the value, so the shadow is
  `rgba(var(--oc-black-rgb, 0, 0, 0), 0.15)` (S063).

## Enforcement
- A Vitest test requires a fallback on every `var(--oc-` in every stylesheet under
  `assets/stylesheets/`, and compares each `ai_helper.css` declaration, resolved
  as Redmine 7 (fallbacks removed) and Redmine 6 (fallbacks applied), with a
  contract table. A new `var(--oc-*)` fails until it is added to the table (S063).
- jsdom does not compute `var()`, so the test resolves it with its own small
  function, which throws on unbalanced parentheses. The CSS rule parser was moved
  to a shared test helper for reuse (S063).
- Browser checks on real Redmine 6 and 7 are manual (quickstart); CI has no setup
  for two Redmine versions (S063).

## Rejected alternatives
- **Version class on `body`, per-version rules**: doubles the rules and needs a
  hook change (S063).
- **Bundling Open Color, defining `:root` variables**: Redmine 6 would show Open
  Color values, and Redmine 7 would get a competing definition (S063).
- **Redmine 6 declaration written before the `var()` one**: the later declaration
  becomes invalid and the earlier one is not used, which is the bug itself (S063).
- **Only checking that a fallback exists**: a wrong value would pass (S063).
- **Playwright comparison of Redmine 6 and 7**: no CI setup for two versions (S063).
