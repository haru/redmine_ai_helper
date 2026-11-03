# CRF-098: Completion init() ran outside the guard that destroys the instance on failure

**Date**: 2026-11-03
**Source**: GitHub Copilot (PR #552)
**Feature**: branch `feature/085-journal-edit-typo-completion` / PR #552
**Files**: assets/javascripts/autocompletion/ai_helper_journal_edit_aids.js, test/javascript/autocompletion/ai_helper_journal_edit_aids.test.js
**Category**: error-handling
**Related**: CRF-095, CRF-061

## Feedback

`autoCompletion.init()` was called before the `try` block whose `catch` calls
`autoCompletion.destroy()`. `init()` creates the overlay and registers the
listeners and only then calls `loadSettings()`, which does `JSON.parse` on a
saved localStorage value. A malformed value throws after the overlay and
listeners exist, so `scan()` marked the form as failed but nothing released
them. (Review comment:
https://github.com/haru/redmine_ai_helper/pull/552#discussion_r4456118864)

## Original Code

```js
const autoCompletion = new window.AiHelperAutoCompletion(textarea, { ... });
autoCompletion.init();

try {
  const typoChecker = new window.AiHelperTypoChecker(textarea, { ... });
  ...
} catch (error) {
  autoCompletion.destroy();
  throw error;
}
```

## Fix

`autoCompletion.init()` moved inside the `try`, so a throw from any step of
`init()` reaches the `catch` that calls `destroy()`. A new test makes
`loadSettings()` throw after the overlay is created and asserts that
`destroy()` ran once, nothing was registered and no overlay remains; it failed
before the change.

## Root Cause

CRF-095 added the destroy-on-failure guard for the step the AI had in mind
(the typo checker) and placed it around the code that follows `init()`. It
treated `init()` as the construction step that "creates" the instance, not as
a step that can fail halfway after it has already created DOM and listeners.
The existing test only made the typo checker's `init()` throw, so it did not
reveal the gap.

## Prevention

When a guard destroys an object on failure, the guard starts at the first call
that allocates anything (overlay, listener, timer) for that object, and that
includes the object's own `init()`/`start()`. For each such call, add a test
that throws from the last step inside it and asserts that `destroy()` ran.

**Promoted to**: Not yet
