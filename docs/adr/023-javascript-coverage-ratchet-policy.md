# ADR-023: JavaScript coverage ratchet from measured baseline to 90%, distinct from Ruby's 95%

**Date**: 2026-08-22
**Status**: Accepted

## Context

The Ruby side enforces 95% test coverage as a hard gate. `assets/javascripts/`
started at effectively 0% (no runnable tests existed). Getting to any fixed
target in one change is impractical: the 12 files total ~5,055 lines, several
are large (up to ~1,080 lines) and mix DOM-wiring code with pure logic, and
some pure logic is embedded inside event handlers or SSE callbacks that need
extraction before it's easily testable (see the plan's staged rollout,
stages 3-4).

Requiring 90% (or any high bar) immediately would force either shipping the
whole feature as one large, hard-to-review change, or temporarily excluding
untested files from the coverage denominator — which would hide, not
measure, the gap.

## Decision

- `vitest.config.js`'s `coverage.thresholds.lines` starts at the coverage
  actually measured once the first tests exist (stage 1: ~4.95%, rounded
  down to `4` for a safe margin against measurement noise), and is raised
  — **never lowered** — at each subsequent stage boundary as more files gain
  tests, until it reaches **90%**.
- All 12 files under `assets/javascripts/` stay in the coverage denominator
  from the start (`coverage.include` covers the whole directory,
  `coverage.exclude` excludes nothing under it) — an untested file counts
  as 0%, not as absent. `coverage.thresholds.perFile` is `false`: only the
  overall percentage is gated, so no single file is required to individually
  clear a bar.
- The target is **90%**, not Ruby's 95%. JavaScript here has a
  meaningfully higher proportion of DOM-wiring code (event listeners, SSE
  streaming callbacks, `DOMContentLoaded` bootstrapping) than the Ruby
  codebase does, and jsdom-based tests of pure DOM plumbing have a lower
  ratio of defect-detection value to writing/maintenance cost. Chasing 95%
  here would incentivize low-value tests just to move the number.
- Ruby and JavaScript coverage are tracked and gated **separately** — they
  are not combined into one metric, and JavaScript coverage is not sent to
  Codecov (only Ruby's `coverage/` output is).

## Consequences

- Coverage can only go up over a file's/stage's history; a PR that would
  lower the recorded threshold should be rejected in review. The threshold
  value's `git blame` is the audit trail for this.
- Because untested files count as 0% in the shared denominator, the overall
  percentage understates how well-tested any *individual* already-covered
  file is — the HTML report (`coverage-js/index.html`) is the right place to
  check a specific file's coverage.
- Contributors adding a new file to `assets/javascripts/` should expect the
  next threshold bump to account for it; an untested new file will lower the
  overall percentage until it gets tests.

## Alternatives Considered

- **Start at 90% (or match Ruby's 95%) immediately**: would have forced
  either a single massive PR covering all 12 files, or excluding untested
  files from the denominator to hit the number artificially — both rejected.
- **Per-file coverage minimums (`coverage.thresholds.perFile: true`)**: would
  block merging any change to a large, not-yet-refactored file until it
  individually hits the bar, which conflicts with the staged rollout plan
  (some files are deliberately covered only in a later stage).
- **Combine Ruby and JavaScript coverage into one number**: would obscure
  which side regressed and forces one target to fit two very different
  codebases; kept as explicitly out of scope.
