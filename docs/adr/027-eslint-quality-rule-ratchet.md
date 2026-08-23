# ADR-027: ESLint naming/explicitness/size/complexity rules start at a measured baseline and ratchet down

**Date**: 2026-08-23
**Status**: Accepted

## Context

`eslint.config.js` (added in issue-046) only covered correctness (`eslint:recommended`,
`no-var`, `prefer-const`, `no-unused-vars`). There was no rule for naming
consistency, explicitness (`==` vs `===`, missing braces, implicit type
coercion), file/function size, or cyclomatic complexity/nesting depth.

Adding these rules at a strict, "ideal" threshold immediately (e.g. the
300-line file / 30-line function / complexity-10 targets suggested by common
ESLint style guides) would fail CI outright: several existing files and
functions predate any size/complexity gate and are well over such targets
(e.g. `ai_helper_typo_checker.js` is 1092 lines; `ai_helper_markdown_parser.js`'s
`processLists` has a cyclomatic complexity of 30). Fixing all of that as a
prerequisite to adding the lint rule would force one large, high-risk
refactor instead of incremental improvement.

## Decision

- Add `camelcase`, `eqeqeq` (`"smart"` — allows the `== null` idiom),
  `curly`, `no-implicit-coercion`, `max-lines`, `max-lines-per-function`,
  `complexity`, `max-depth`, and `max-params` to `eslint.config.js`, split
  between the `assets/javascripts/**` and `test/javascript/**` blocks with
  independently measured thresholds.
- Every numeric threshold is set from the value actually measured in the
  codebase on 2026-08-23 (via `eslint --rule '{"<rule>": ["error", 1]}'`,
  which forces every location to report its actual value), not from an
  external style guide's ideal target. Initial baseline when the rules were
  added:
  - `assets/javascripts/**`: `max-lines` 1092 -> 1100, `max-lines-per-function`
    418 -> 420, `complexity` 30, `max-depth` 6, `max-params` 6.
  - `test/javascript/**`: `max-lines` 1493 -> 1500, `complexity` 12,
    `max-depth` 2, `max-params` 3. `max-lines-per-function` is not enforced
    for tests: Vitest files wrap their entire contents in one outer
    `describe()` callback by convention, so that callback's line count
    reflects the whole file's length, not a real maintainability problem.
  - Same policy as `vitest.config.js`'s coverage threshold (ADR-023):
    thresholds are only ever lowered (tightened), never raised, as files and
    functions get split up.
  - That policy took effect immediately: the same PR that introduced these
    rules also split every file/function over the ideal targets, so the
    thresholds actually committed to `eslint.config.js` are already tighter
    than this initial baseline — currently `max-lines` 400,
    `max-lines-per-function` 130, `complexity` 14, `max-depth` 3,
    `max-params` 6 for `assets/javascripts/**`. `eslint.config.js` is the
    source of truth for the current numbers; a threshold's `git blame` there
    is the audit trail for when and why it moved (see Consequences).
- `camelcase`, `eqeqeq`, `curly`, and `no-implicit-coercion` have no
  meaningful "threshold" to ratchet (they're pass/fail), so instead of
  starting loose, the ~168 existing violations were fixed directly: the
  ~100 missing-brace and 1 `==` case were mechanical (`npm run lint:fix`,
  no behavior change), and the ~13 `camelcase` violations were either
  genuinely local variables (renamed: `disable_animation`/`arrow_down`/
  `arrow_left` in `ai_helper.js`'s `fold_chat`) or intentional ERB<->JS
  bridge identifiers that mirror the Ruby/ERB side's snake_case naming
  (`ai_helper`, `ai_helper_urls`, `ai_helper_generate_reply`), which are
  listed in `camelcase`'s `allow` option rather than renamed — renaming
  those would require an ERB template change out of scope for a lint
  config PR, and they're already documented bridge names in the `globals`
  block.

## Consequences

- `npm run lint` enforces all five quality categories (naming, explicitness,
  unused-code detection, size limits, complexity) from this change onward,
  with zero new violations against the measured baseline.
- A threshold's `git blame` is the audit trail for when it was tightened;
  a PR that raises one of these numbers back up should be rejected in
  review, same as the coverage ratchet.
- Contributors splitting up a large file/function should lower the
  corresponding threshold in the same PR rather than leaving it at the old,
  now-inaccurate ceiling.
- The `camelcase` `allow` list is a deliberate, narrow exception for
  documented ERB<->JS bridge names — not a general escape hatch. Adding to
  it should be as rare as adding to the `globals` block.

## Alternatives Considered

- **Adopt the strict targets from common style guides immediately**:
  rejected — would fail CI on adoption and force an unrelated, high-risk
  mass refactor as a prerequisite.
- **Add the rules as `"warn"` instead of `"error"` until the codebase catches
  up**: rejected — warnings are routinely ignored in practice (no such
  policy exists elsewhere in this repo's lint/coverage setup), and `"error"`
  at a truthful baseline gives the same immediate signal on regressions
  without that risk.
- **Silence the `camelcase` violations on bridge identifiers with inline
  `/* eslint-disable */` comments**: rejected — AGENTS.md's linting
  guidance explicitly prohibits working around a violation with an inline
  disable instead of a `globals`/config-level declaration.
