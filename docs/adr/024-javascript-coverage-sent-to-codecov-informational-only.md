# ADR-024: JavaScript coverage is uploaded to Codecov as an informational-only flag

**Date**: 2026-08-22
**Status**: Accepted — amends the Codecov clause of [ADR-023](./023-javascript-coverage-ratchet-policy.md)

## Context

ADR-023 decided that JavaScript coverage would not be sent to Codecov at
all, to avoid moving the developer-referenceable coverage record outside
the repo and to avoid any risk of Codecov's own coverage check gating PRs
independently of the local `vitest.config.js` threshold.

In practice, contributors want the same PR-level visual feedback for
JavaScript that Codecov already gives for Ruby (diff coverage annotations,
trend history), without changing who actually decides pass/fail. The
`javascript` CI job already produces `coverage-js/lcov.info`
(`vitest.config.js`'s `coverage.reporter` includes `lcov`), so uploading it
costs nothing beyond one more CI step.

## Decision

- The `javascript` job in `.github/workflows/build.yml` uploads
  `coverage-js/lcov.info` to Codecov via `codecov/codecov-action@v7`, tagged
  with `flags: javascript`. The existing Ruby upload in the `build` job is
  tagged `flags: ruby`.
- `codecov.yml` (new, repo root) turns off the default flag-less
  project/patch checks (`default: false`) and defines two separate checks:
  - `ruby` — `informational: false`, i.e. it can still fail a PR check, same
    as the existing (unconfigured) behavior before this ADR.
  - `javascript` — `informational: true`, i.e. it is always green and never
    fails a PR check. It exists purely for the diff-coverage comment and the
    Codecov UI's per-flag trend graph.
- The pass/fail gate for JavaScript coverage remains exactly what ADR-023
  established: `vitest.config.js`'s `coverage.thresholds.lines`, enforced
  identically by `npm run test:coverage` in CI and in
  `.devcontainer/regression-check.sh`. Codecov's javascript flag cannot fail
  a build; nothing about the ratchet policy or FR-026 local/CI parity
  changes.
- Ruby and JavaScript coverage are still never combined into one number —
  they are separate Codecov flags with separate, non-carried-forward paths
  (`flags.ruby.paths: [lib/, app/]`, `flags.javascript.paths:
  [assets/javascripts/]`).

## Consequences

- PRs that touch `assets/javascripts/` now get a Codecov diff-coverage
  comment for JavaScript, same as Ruby changes already do.
- A `CODECOV_TOKEN` secret is required for the upload step to run (guarded
  by the same `if: env.CODECOV_TOKEN != ''` pattern already used for Ruby);
  its absence does not fail the job.
- If someone later wants Codecov to actually gate JavaScript PRs, that
  requires an explicit further decision (flip `informational` to `false`)
  — this ADR does not authorize that on its own.

## Alternatives Considered

- **Keep JavaScript coverage out of Codecov entirely** (ADR-023's original
  position): simplest, but gives up PR-level diff-coverage visibility that
  the Ruby side already has, for no remaining benefit once flags keep the
  numbers separate and informational-only removes the gating risk.
- **Let Codecov gate JavaScript PRs too** (`informational: false` for the
  `javascript` flag): would introduce a second place (besides
  `vitest.config.js`) that decides pass/fail, breaking the local/CI parity
  ADR-023 and FR-026 require. Rejected.
