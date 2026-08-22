# Repository Guidelines — `assets/javascripts/`

Scope: this file governs `assets/javascripts/**` and its tests in
`test/javascript/**`. See the repository-root `AGENTS.md` for everything
else (Ruby, agents, tools, git workflow).

## Constraints

- These are **classic scripts** loaded via `javascript_include_tag`, not ES
  modules — there is no bundler and no build step for production code.
  **Never add `import`/`export` to a file under `assets/javascripts/`.**
- Vanilla ES6 only: `const`/`let` and classes. No `var`, no jQuery.
- Never build HTML in JavaScript (XSS prevention) — HTML lives in ERB
  templates only.
- A class or function other files depend on must be exposed as
  `window.X = X;` (a plain top-level `class X {}` alone is not enough once
  the file is evaluated as a module by the test runner). Adding this line is
  the only kind of change allowed purely to make a file testable — don't add
  test-only branches or UMD-style export shims.
- Any new cross-file global (or one supplied by an ERB inline script) must
  be declared in `eslint.config.js`'s `languageOptions.globals` for the
  `assets/javascripts/**` block — don't silence it with an inline
  `/* eslint-disable */` instead.

## Documentation

- Write comments in English.
- Document every class and every non-trivial method with JSDoc
  (`@param`, `@returns`, and a one-line description). Keep it factual — the
  same "document the why, not the what" standard as code comments applies
  to the description line; `@param`/`@returns` should still state the type
  and meaning of each value.

## Testing

- TDD: write the test before (or alongside) the implementation for new
  logic; when refactoring existing untested code, write a characterization
  test that pins current behavior first, then refactor without changing it.
- Framework: Vitest (`environment: 'jsdom'`). Tests live in
  `test/javascript/**/*.test.js`, one test file per target script.
- A target script has no `import`/`export`, so load it with a side-effect
  dynamic `import()` (see `test/javascript/support/`), and call
  `vi.resetModules()` first so each test starts from a clean module cache.
  For a file that initializes on `DOMContentLoaded`, dispatch
  `document.dispatchEvent(new Event('DOMContentLoaded'))` after importing it
  — jsdom's `readyState` is already `complete` at import time.
- Stub `fetch` / `XMLHttpRequest` (`vi.fn()`, `vi.stubGlobal()`); tests must
  never hit a real server or AI backend.
- Tests must not depend on execution order — don't leak state between
  tests via a global that isn't reset.
- Every new or changed file's coverage must not lower the ratchet in
  `vitest.config.js`'s `coverage.thresholds.lines`. Raise it, never lower
  it, when a change measurably improves coverage.

## Linting

- Run `npm run lint` after any change under `assets/javascripts/` or
  `test/javascript/` and fix all offenses before finishing; `npm run
  lint:fix` applies ESLint's auto-fixes first.
- Don't work around a lint violation with an inline disable comment or an
  ignore-list entry — fix the code, or (for a genuinely needed global)
  declare it in `eslint.config.js`.

## Commands

Run from the plugin directory (`plugins/redmine_ai_helper`); requires
Node.js >= 22 (`npm ci` once to install):

```bash
npm run lint           # ESLint over assets/javascripts/ and test/javascript/
npm run lint:fix       # Auto-fix what ESLint can fix
npm test               # Vitest (jsdom, no browser/network)
npm run test:coverage  # Vitest + coverage threshold gate
```

`.devcontainer/regression-check.sh` runs the same lint/test/coverage gate
before the Ruby test suite — a change here is not done until that gate
passes locally.

## Reference

- [docs/javascript_quality_tooling.md](../../docs/javascript_quality_tooling.md)
- [ADR-022](../../docs/adr/022-javascript-test-tooling-for-classic-scripts.md) — dynamic-import test strategy
- [ADR-023](../../docs/adr/023-javascript-coverage-ratchet-policy.md) — coverage ratchet policy
- Wiki: `wiki/pages/js-quality-tooling.md`,
  `wiki/pages/classic-script-testing-strategy.md`,
  `wiki/pages/js-coverage-ratchet-policy.md`,
  `wiki/pages/js-test-convention.md`
