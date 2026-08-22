---
title: Browser-Side JavaScript Tests
type: howto
sources: [S021, S023]
updated: 2026-08-21
---

# Browser-Side JavaScript Tests

The repository has **no JavaScript test runner**: there is no `package.json`, and
`.devcontainer/regression-check.sh` runs YARD doc coverage, RuboCop and the Ruby
test suite only (S021).

## The established convention

Files under `test/javascript/` are self-contained, jsdom-style test files that
build their own minimal DOM. They serve a double role, stated in the header
comment of `ai_helper_command_completion_test.js` (S021):

1. runnable as-is **if** a Jest + jsdom environment is available, and
2. otherwise the written specification for manual verification of the same cases.

Follow that format when adding a test for browser behaviour — e.g.
`ai_helper_auto_completion_test.js` covers abort-on-new-request, snapshot
comparison and debounce-timer clearing for the
[inline completion flow](./inline-completion-request-flow.md) (S021).

## Assertions must be able to fail

`console.assert` neither throws nor returns anything, so a file that used it
printed its own `PASSED` line whatever the assertions found — a failing test and
a passing one looked identical. `ai_helper_auto_completion_test.js` therefore
routes every assertion through a `check(condition, message)` helper that counts
failures, and a `runTest(name, fn)` runner that prints `PASSED` only for a test
that recorded none, catches an exception thrown inside a test, and lets
`runAllTests()` return the total number of failed assertions (S023).

Keep that shape when adding a browser test: an assertion that cannot fail is
worse than no assertion, because it reads as coverage.

## What this means for coverage

The constitution's 95 % coverage rule applies to the Ruby code measured in
`coverage/`; browser-side changes are covered by the convention above, and the
Ruby half of any such feature is still expected to be developed test-first
(S021).

## Verifying measurable browser behaviour

Success criteria that are timing- or network-observational (concurrent
connections, time-to-save) are verified manually through the feature's
`quickstart.md`: drive the running Redmine with Playwright MCP (the
`redmine-playwright-login` skill) and watch the browser's network recording
(S021).

## Deliberately not adopted

Introducing Jest + jsdom as a devDependency and wiring it into CI was considered
and **deferred** — standing up a test framework exceeds the scope of a bug fix,
and the feature's clarifications explicitly ruled out new E2E infrastructure. It
remains reasonable as an independent future improvement (S021).

## Related

- [Inline Completion Request Flow](./inline-completion-request-flow.md) ·
  [AI Chat Sidebar](./chat-sidebar.md) · [Plugin Overview](./plugin-overview.md)
