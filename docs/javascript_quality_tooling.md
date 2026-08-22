# JavaScript Quality Tooling

This plugin's `assets/javascripts/` code (the classic browser scripts loaded
via `javascript_include_tag`) is covered by the same kind of quality gate as
the Ruby side: static analysis (ESLint), automated tests (Vitest), and a
coverage threshold. This document explains what runs, why, and how to set up
a development environment for it.

Node.js is a **development-time requirement only**. Plugin users (Redmine
operators) never need it — no build step is required to run the plugin, and
no build artifacts are shipped.

## Requirements

- Node.js >= 22 (the devcontainer already has v24 installed via nvm).
- npm (bundled with Node.js).

Check with:

```sh
node -v
npm -v
```

## Setup

From the plugin root (`plugins/redmine_ai_helper/`):

```sh
npm ci
```

This installs the exact versions recorded in `package-lock.json`. It runs
automatically in the devcontainer via `.devcontainer/post-create.sh`.

## Commands

All commands run from the plugin root.

| Command | Purpose |
|---|---|
| `npm run lint` | ESLint over `assets/javascripts/**/*.js` and `test/javascript/**/*.js`. Exit code 0 means no violations. |
| `npm run lint:fix` | Same, but auto-fixes what ESLint can fix (e.g. `var` -> `let`/`const` in block scope). Review the diff afterward. |
| `npm test` | Runs the Vitest suite (`test/javascript/**/*.test.js`) in jsdom. No browser, no network access. |
| `npm run test:coverage` | Same, plus a coverage report and threshold check. Fails if line coverage drops below the threshold in `vitest.config.js`. |

These are the same commands run in CI (the `javascript` job in
`.github/workflows/build.yml`) and in `.devcontainer/regression-check.sh`, so
a local pass means CI will pass too.

## How classic scripts are tested

The files under `assets/javascripts/` are not ES modules — they're loaded
directly as browser `<script>` tags and can't use `export`/`import` without
changing how Redmine serves them. Tests instead load each file with a
side-effect-only dynamic `import()` (see
`test/javascript/support/load_script.js`) inside a jsdom environment, then
assert against whatever the file attaches to `window`. See
[ADR-022](adr/022-javascript-test-tooling-for-classic-scripts.md) for the
full rationale.

## Coverage threshold ratchet

`vitest.config.js`'s `coverage.thresholds.lines` starts at the coverage
measured when the first tests were added, and is only ever raised (never
lowered) as more files get test coverage, until it reaches 90%. See
[ADR-023](adr/023-javascript-coverage-ratchet-policy.md) for why the target
differs from the Ruby side's 95%.

To see which lines are still untested, open the HTML report after running
`npm run test:coverage`:

```sh
open coverage-js/index.html   # or your OS's equivalent
```

## Codecov

CI also uploads `coverage-js/lcov.info` to Codecov under the `javascript`
flag, purely for visualization (PR diff-coverage comments, trend graphs).
It never gates a PR — `javascript` is configured as an informational-only
check in `codecov.yml`, kept separate from the `ruby` flag. The actual pass/
fail gate stays local: `vitest.config.js`'s `coverage.thresholds.lines`,
enforced by `npm run test:coverage` in both CI and
`.devcontainer/regression-check.sh`. See
[ADR-024](adr/024-javascript-coverage-sent-to-codecov-informational-only.md).
