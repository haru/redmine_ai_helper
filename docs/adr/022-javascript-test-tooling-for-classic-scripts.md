# ADR-022: Vitest + jsdom for testing classic scripts via side-effect dynamic import

**Date**: 2026-08-22
**Status**: Accepted

## Context

`assets/javascripts/` (12 files, ~5,055 lines) had no automated tests or
static analysis, unlike the Ruby side (shoulda/mocha, 95% coverage,
RuboCop). A handful of `test/javascript/*_test.js` files existed, written
against `console.assert` with no runner — they were never actually executed
and required manual verification.

These files are loaded by `javascript_include_tag` as plain, non-module
browser scripts across four different ERB templates, some loaded more than
once (hence the `if (typeof X === 'undefined')` load guards seen in several
files). Adding `export`/`import` to them would require switching Redmine's
script loading to `type="module"`, which is out of scope and risks changing
load-order-dependent behavior between files. Distribution and runtime must
stay build-free (Redmine operators install/run the plugin with no Node.js
and no build step).

## Decision

- Use **Vitest** (test runner + assertions) with the **jsdom** environment,
  and **`@vitest/coverage-v8`** for coverage. One tool covers both testing
  and coverage (no separate Istanbul/nyc setup).
- Tests load each target file via a **side-effect-only dynamic `import()`**
  (`test/javascript/support/load_script.js`), preceded by `vi.resetModules()`
  so each load starts from a clean module registry. Vitest evaluates dynamic
  imports as ES modules regardless of whether the source uses
  `export`/`import`, which means:
  - The file executes for its side effects (assigning to `window`,
    registering `DOMContentLoaded` listeners, etc.) without needing any
    production code changes to add module syntax.
  - `@vitest/coverage-v8` instruments it, unlike a plain `fetch`-and-`eval`
    approach, which would run the code outside Vitest's transform pipeline
    and produce no coverage data.
- Files with **zero exposed globals** needed one addition:
  `window.X = X;` at the end of the file, so the (otherwise block/module
  -scoped) top-level `class X {}` or function becomes reachable from the
  test. This is strictly additive — it does not change what already-working
  inline `onclick` handlers or same-file references resolve to, because
  script-mode top-level classes were never `window` properties to begin
  with, whether run as a plain `<script>` or as an ES module under test.
  One special case: `assets/javascripts/ai_helper.js`'s
  `var ai_helper = new AiHelper();` was replaced with
  `window.AiHelper = AiHelper; window.ai_helper = new AiHelper();` — under
  `var`, the bare identifier already resolved via the global object, so this
  preserves both the bare-identifier and `window.`-qualified reference paths
  used by inline ERB scripts and `onclick` attributes.
- Global identifiers supplied by other files or by ERB inline `<script>`
  tags (e.g. `ai_helper_urls`, `getSummary`) are declared in
  `eslint.config.js`'s `languageOptions.globals` rather than exposed via
  `/* global */` comments scattered across files, so the full cross-file
  dependency surface is visible in one place.

## Consequences

- Tests run in milliseconds without a browser (jsdom), keeping the suite
  fast (well under the 60s target) and network-free.
- The only production code changes required were additive
  (`window.X = X;` lines) or a single behavior-preserving `var` ->
  `window` assignment rewrite — no ERB templates, load order, or
  `javascript_include_tag` calls changed.
- Test authors must remember that classic scripts are evaluated fresh per
  `loadScript()` call (via `vi.resetModules()`); state that should persist
  across "page loads" within one test needs explicit setup, mirroring how a
  real page reload would reset it too.

## Alternatives Considered

- **Read the file source and `eval` it in the jsdom `window` context**:
  avoids touching production code at all, but bypasses Vitest's transform
  pipeline, so `@vitest/coverage-v8` cannot instrument it — coverage
  reporting (a core requirement) would not work.
- **Add a UMD-style export branch to each file**: keeps a "real" module
  export path, but adds test-only branching logic to production code,
  which the project's simplicity guidelines (KISS/YAGNI) argue against
  when a single additive `window.X = X;` line achieves the same result.
- **Migrate to ES modules and `type="module"` script tags**: the most
  "modern" option, but is a larger, riskier change to load order and
  cross-file global coordination that is out of scope for adding a test
  harness.
- **Jest + jsdom**: comparable capability, but ESM handling requires extra
  transform configuration; Vitest's native ESM support and built-in
  coverage/threshold handling needed less glue code.
