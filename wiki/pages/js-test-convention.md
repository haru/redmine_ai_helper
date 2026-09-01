---
title: Browser-Side JavaScript Tests
type: howto
sources: [S021, S023, S024]
updated: 2026-08-22
---

# Browser-Side JavaScript Tests

As of feature 046, the repository has a real JavaScript test runner: ESLint
10 (flat config) + Vitest 4 (jsdom) + `@vitest/coverage-v8`, wired into
`.devcontainer/regression-check.sh` and a dedicated CI job. See
[JavaScript Quality Tooling](./js-quality-tooling.md) for the toolchain and
[Testing Classic Scripts via Dynamic Import](./classic-script-testing-strategy.md)
for how the classic (non-module) scripts under `assets/javascripts/` get
tested without a build step (S024). This superseded the no-runner convention
described below.

## Superseded: the self-contained test-file convention (pre-046)

Before feature 046, the repository had **no JavaScript test runner**: no
`package.json`, and `regression-check.sh` ran YARD doc coverage, RuboCop and
the Ruby test suite only (S021).

Files under `test/javascript/` were self-contained, jsdom-style test files
that built their own minimal DOM, serving a double role stated in the header
comment of `ai_helper_command_completion_test.js` (S021):

1. runnable as-is **if** a Jest + jsdom environment was available, and
2. otherwise the written specification for manual verification of the same
   cases.

Introducing Jest + jsdom as a devDependency was considered at the time and
explicitly **deferred** as exceeding a bug fix's scope (S021). Feature 046
later adopted this — as Vitest, not Jest — and phases 1–2 of its rollout
replaced these self-contained files with real Vitest tests under
`test/javascript/**/*.test.js` (S024).

## Assertions must be able to fail (the lesson that carried over)

`console.assert` neither throws nor returns anything, so a file that used it
printed its own `PASSED` line whatever the assertions found — a failing test
and a passing one looked identical. The old convention's fix was a
`check(condition, message)` helper that counted failures and a `runTest`
runner that printed `PASSED` only when none were recorded (S023). Vitest's
`expect()` satisfies this requirement natively — it throws on failure — so
new tests no longer need a hand-rolled equivalent; the lesson (an assertion
that cannot fail is worse than no assertion) is why that property mattered
(S023).

## What this means for coverage

The Ruby constitution's 95% coverage rule still applies only to the Ruby
code measured in `coverage/`, unchanged. JavaScript now has its own
coverage gate, tracked separately at 90% — see
[JavaScript Coverage Ratchet Policy](./js-coverage-ratchet-policy.md). The
two are deliberately not merged into one figure (S024).

## Verifying measurable browser behaviour

Success criteria that are timing- or network-observational (concurrent
connections, time-to-save) are still verified manually through a feature's
`quickstart.md`: drive the running Redmine with Playwright MCP (the
`redmine-playwright-login` skill) and watch the browser's network recording
(S021).

## Related

- [JavaScript Quality Tooling](./js-quality-tooling.md)
- [Testing Classic Scripts via Dynamic Import](./classic-script-testing-strategy.md)
- [JavaScript Coverage Ratchet Policy](./js-coverage-ratchet-policy.md)
- [Inline Completion Request Flow](./inline-completion-request-flow.md) ·
  [AI Chat Sidebar](./chat-sidebar.md) · [Plugin Overview](./plugin-overview.md)
