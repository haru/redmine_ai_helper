---
title: JavaScript Quality Tooling
type: component
sources: [S024]
updated: 2026-08-22
---

# JavaScript Quality Tooling

Feature 046 gave `assets/javascripts/` the same kind of quality gate Ruby
already had: static analysis, automated tests, and a coverage ratchet, wired
into both the devcontainer regression check and CI (S024).

## Toolchain

- **Runtime**: Node.js 24 (`engines.node >= 22` in `package.json`) + npm.
  Nothing is added to `.devcontainer/Dockerfile` — the base image
  (`haru/redmine_devcontainer`) already provides Node 24.18.0 via nvm, and
  installing it a second way would fight nvm for `PATH`. `package-lock.json`
  is committed so `npm ci` gives a reproducible install; `post-create.sh` runs
  `npm ci` automatically (S024).
- **Lint**: ESLint 10.9.0, flat config only, one file: `eslint.config.js`.
- **Test**: Vitest 4.1.11 with `environment: 'jsdom'` (jsdom 30.0.1) — chosen
  over Jest+jsdom (ESM setup friction with the dynamic-import loading style,
  see [Testing Classic Scripts via Dynamic Import](./classic-script-testing-strategy.md)),
  `node:test` (would need jsdom, coverage gating, and reporting hand-built),
  and browser-mode/Playwright runners (out of scope, worse for the time
  budget) (S024).
- **Coverage**: `@vitest/coverage-v8` — see
  [JavaScript Coverage Ratchet Policy](./js-coverage-ratchet-policy.md).
- All five packages are `devDependencies`; production dependency count is 0
  (S024).
- pnpm/yarn and Bun/Deno were considered and rejected: pnpm/yarn add setup
  cost for no benefit over 5 devDependencies; Bun/Deno bundle a test runner
  and coverage but would add a second JS runtime to the container and CI,
  with a weaker ESLint track record (S024).

## ESLint configuration

One `eslint.config.js` at the repo root, with separate rule sets for
`assets/javascripts/**` and `test/javascript/**`. The production rule set
maps directly to what static analysis must catch: `no-undef` (undefined
references), `no-unused-vars`, `no-var` (explicit `error` — not in
`recommended`), `no-unreachable`, `no-constant-condition` and
`no-constant-binary-expression`, plus parse errors reported automatically
(S024).

Browser/plugin globals are declared explicitly in
`languageOptions.globals` — `globals.browser` plus an enumerated list, rather
than turning `globals` off (too many false positives from Redmine/browser
globals) or leaving it wide open (misses real typos):

- ERB-supplied: `ai_helper_urls`, `ai_helper`
- Shared classes: `AiHelper`, `AiHelperMarkdownParser`,
  `AiHelperTypoChecker`, `AiHelperMasterDetail`, `AiHelperAutoCompletion`,
  `AiHelperAssignmentSuggestion`, `CommandCompletion`
- Reload guards: `aiHelperComparisonInitialized`,
  `aiHelperProjectHealthInitialized`, `aiHelperProjectHealthLoaded`,
  `aiHelperStuffTodoInitialized`, `aiHelperInstances`
- Cross-file functions: `updateComparisonButton`, `updateHealthReportHistory`

This list doubles as a ledger of the plugin's cross-file global dependencies.
The alternative — a `/* global ... */` comment per file — was rejected: it
scatters lint-only comments across 12 production files and loses the
whole-picture view this list gives (S024).

Biome and JSHint/StandardJS were considered for lint and rejected: Biome's
global-resolution equivalent to `no-undef` is weak for classic (non-module)
scripts; JSHint/StandardJS can't express per-directory rule sets, which the
production/test split above needs (S024).

## Wiring into regression-check.sh and CI

`.devcontainer/regression-check.sh` fails fast with a clear message if `npm`
is missing (never a silent skip), runs `npm ci` automatically if
`node_modules/` is absent, and runs the JS checks before the heavier Ruby
tests so feedback comes early. `.github/workflows/build.yml` has one
independent `javascript` job — not folded into the existing `lint`
(RuboCop) or `build` (Ruby matrix) jobs, so a JS failure and a Ruby failure
are never conflated — added to the `notify` job's `needs` (S024).

## Refactoring convention

When a file needs logic pulled out for testability, extract it as a
top-level function or static method **within the same file** — never a new
file. A new file would need a new `javascript_include_tag` and could disturb
the existing script load order, which this tooling must not change (S024).

## Related

- [Testing Classic Scripts via Dynamic Import](./classic-script-testing-strategy.md)
- [JavaScript Coverage Ratchet Policy](./js-coverage-ratchet-policy.md)
- [Browser-Side JavaScript Tests](./js-test-convention.md)
