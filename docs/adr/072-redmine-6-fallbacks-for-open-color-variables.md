# ADR-072: Redmine 6 fallbacks for Open Color variables

**Date**: 2026-11-21
**Status**: Accepted

## Context

- Redmine 7 defines the Open Color variables (`--oc-gray-0`, `--oc-white`,
  `--oc-black-rgb` and so on) on `:root`. Redmine 6.0 and 6.1 define none of them.
- The plugin supports Redmine 6.0 and later. Nine declarations in
  `assets/stylesheets/ai_helper.css` (the popup background, border, shadow and
  rule colour, and the reply "Apply" button colours) used the variables with no
  fallback. In Redmine 6 a declaration that refers to an undefined variable is
  invalid at computed-value time, so the property falls back to its initial
  value (transparent) instead of the earlier declaration. The popup became
  see-through and the button lost its colours (issue #570).

## Decision

- Whenever a plugin stylesheet uses `var(--oc-*)`, it gives a non-empty fallback:
  `var(--oc-gray-0, #f9fafb)`. Redmine 7 defines the variable, so the fallback is
  ignored and the colour is unchanged.
- The fallback is the value Redmine 6 uses for the same element and state, taken
  from the same selector in Redmine 6's `application.css`. When Redmine 6 has no
  counterpart, the value is decided with the maintainer instead of being filled
  in from another version or from Open Color.
- A Vitest test (`ai_helper_redmine_version_colors_css.test.js`) enforces it. It
  requires a fallback on every occurrence in every stylesheet, and compares each
  `ai_helper.css` declaration, resolved as Redmine 7 (fallbacks removed) and as
  Redmine 6 (fallbacks applied), with a contract table. A new declaration that
  uses `var(--oc-*)` fails the test until it is added to the table.

## Consequences

- Redmine 6 shows the same colours as Redmine 6's own sidebar and buttons, and
  Redmine 7 is unchanged.
- No server-side version check, no extra rules and no JavaScript or ERB change.
- Each new use of an Open Color variable needs a fallback looked up in Redmine 6
  and a row in the contract table.

## Alternatives Considered

- **A version class on `body` and separate rules per version**: doubles the
  rules and needs a hook change; the fallback of `var()` is enough.
- **Bundling Open Color and defining the variables on `:root`**: Redmine 6 would
  show Open Color values, not its own, and Redmine 7 would get a second definition
  that competes with its own.
- **Writing the Redmine 6 declaration before the `var()` declaration**: in
  Redmine 6 the later declaration is invalid at computed-value time and the
  earlier one is not used, so the property becomes transparent. This is the bug
  itself.
