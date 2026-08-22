---
title: JavaScript Coverage Ratchet Policy
type: decision
sources: [S024]
updated: 2026-08-22
---

# JavaScript Coverage Ratchet Policy

## Decision

`coverage.thresholds.lines` in `vitest.config.js` is a plain numeric literal,
raised as each rollout stage adds tests and never lowered. Enforcement is PR
review plus `git blame` on that line — no separate threshold file and no
external service, so the record and its history live in the same place as
the code (S024).

## Provider and scope

- **Provider**: `@vitest/coverage-v8` — line coverage (C0) only. The feature
  gates on C0, not branch coverage, so the istanbul provider's extra
  precision would cost instrumentation time for no gating benefit (S024).
- **Scope**: `assets/javascripts/**/*.js`, including files no test ever
  exercises — they still count in the denominator, so the gate can't be
  satisfied by quietly leaving a file untested (S024).
- **Reporters**: `text` (CI log), `html` (locate uncovered lines), `lcov`
  (future external integration) (S024).

## Why a separate output directory

Coverage output goes to `coverage-js/`, deliberately separate from Ruby's
SimpleCov `coverage/`. SimpleCov's HTML reporter writes its own `.js` files
into `coverage/`; letting those be swept into JS lint/coverage scope would be
a correctness bug. Separating the output directory *and* scoping both ESLint
and coverage to `assets/javascripts/**` guards against this twice (S024).

## Why 90%, not Ruby's 95%

The target is 90% lines, deliberately different from the Ruby constitution's
95%. This is recorded as an accepted Complexity Tracking deviation: the two
suites are never merged (Ruby's coverage/ measurement and rules are
unchanged), and JS carries a higher share of DOM-wiring code where pushing
past 90% would mean writing tests with little verification value (S024).

Sending JS coverage to Codecov alongside Ruby's existing setup was
considered and rejected — it would keep tooling consistent with the Ruby
side, but moves the "developer-referenceable record" outside the repo and
breaks parity between what CI checks and what `regression-check.sh` checks
locally (S024).

## Related

- [JavaScript Quality Tooling](./js-quality-tooling.md)
- [Testing Classic Scripts via Dynamic Import](./classic-script-testing-strategy.md)
