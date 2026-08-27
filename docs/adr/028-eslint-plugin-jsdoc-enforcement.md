# ADR-028: eslint-plugin-jsdoc enforces the existing JSDoc convention

**Date**: 2026-08-23
**Status**: Accepted

## Context

`assets/javascripts/AGENTS.md` already documented a convention — "Document
every class and every non-trivial method with JSDoc (`@param`, `@returns`,
and a one-line description)" — but nothing in `eslint.config.js` checked it.
Compliance depended entirely on manual review, and in practice about 14 of
25 files had partial JSDoc coverage with no consistent enforcement of
`@param`/`@returns` descriptions or JSDoc syntax validity.

## Decision

- Add `eslint-plugin-jsdoc` as a dev dependency and apply its
  `flat/recommended` rule set to the `assets/javascripts/**` block in
  `eslint.config.js`, scoped there only (not `test/javascript/**`, where
  Vitest's `describe`/`it` structure isn't the kind of API surface this
  convention targets).
- Per this repo's established policy (ADR-027: warnings are routinely
  ignored, so start at "error" with a truthful baseline instead), every
  `jsdoc/*` rule from the recommended preset — which ships at `"warn"` — is
  promoted to `"error"` via a small map in `eslint.config.js`, rather than
  listed rule-by-rule, so a future plugin upgrade that adds a rule to the
  preset inherits the same policy automatically.
- `jsdoc/require-jsdoc`'s default `require` only checks top-level `function`
  declarations. Widened to also require documentation on `ClassDeclaration`,
  `ClassExpression`, and `MethodDefinition` (ES6 class methods) to match
  "every class and every non-trivial method". Additionally targets the
  `foo = function () {}` class-field method style used throughout this
  codebase (e.g. `ai_helper.js`'s `set_form_handlers`, `call_llm`,
  `fold_chat`) via `contexts: ["PropertyDefinition > FunctionExpression",
  "PropertyDefinition > ArrowFunctionExpression"]` — deliberately narrower
  than the blanket `require: { FunctionExpression: true }` option, which
  would also flag every nested callback assigned to a property (e.g.
  `xhr.onload = function () {}` inside a method body). Those are
  implementation detail, not the class/method API surface the convention
  means to document, and requiring JSDoc on them would produce noise
  disproportionate to their value (250+ violations measured vs. 182 with
  the narrower scope).
- All ~182 pre-existing violations measured at adoption (missing JSDoc
  blocks, missing `@param`/`@returns` descriptions, `Object`/`String` type
  names where `jsdoc/check-types` prefers lowercase `object`/`string`) were
  fixed in the same change — consistent with ADR-027's approach to
  pass/fail rules with no meaningful "threshold" to ratchet: fix directly
  rather than start at `"warn"`.

## Consequences

- `npm run lint` now fails on a class, method, or class-field method that's
  missing a JSDoc block, or on a `@param`/`@returns` missing a description
  or using a non-standard type name — from this change onward, not just as
  a documented-but-unenforced convention.
- Nested function expressions and arrow-function callbacks are still not
  required to carry JSDoc, matching AGENTS.md's "non-trivial method" scope
  rather than every closure in the codebase.
- A new file/class/method must be documented when it's added, not
  retrofitted later — the same ratchet-adjacent expectation as ADR-027's
  size/complexity rules.

## Alternatives Considered

- **Adopt `flat/recommended`'s rules and `require-jsdoc` defaults as-is (no
  `require`/`contexts` widening)**: rejected — its default `require` only
  covers top-level `function` declarations, so it would have left every
  class, ES6 method, and class-field method in the codebase unchecked,
  missing the actual convention in AGENTS.md.
- **`require: { FunctionExpression: true }` instead of the narrower
  `contexts` targeting**: rejected — flags every nested callback assigned to
  a property, not just class-field methods, producing ~250 violations
  instead of 182, with the excess being implementation-detail closures
  AGENTS.md's convention was never meant to cover.
- **Add the rules as `"warn"` until the codebase catches up**: rejected for
  the same reason as ADR-027 — warnings are routinely ignored in practice,
  and the 182 violations were small enough to fix directly in the same PR.
