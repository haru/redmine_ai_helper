# CRF-095: Journal edit aids fell back to page-level controls and left half-built forms behind

**Date**: 2026-11-03
**Source**: Local AI review (speckit-review-run: errors, types, code)
**Feature**: branch `feature/085-journal-edit-typo-completion`
**Files**: assets/javascripts/autocompletion/ai_helper_journal_edit_aids.js, assets/javascripts/autocompletion/ai_helper_auto_completion.js, assets/javascripts/typo_checker/ai_helper_typo_checker.js, assets/javascripts/typo_checker/ai_helper_typo_suggestion_overlay.js, test/javascript/autocompletion/ai_helper_journal_edit_aids.test.js, test/javascript/autocompletion/ai_helper_auto_completion.test.js, test/javascript/typo_checker/ai_helper_typo_checker.test.js
**Category**: error-handling
**Related**: CRF-045, CRF-061

## Feedback

- `attach()` threw for a missing textarea but passed the checkbox, check
  button and control panel (`querySelector`, possibly `null`) straight on. The
  components then used their page-level lookups, so a missing checkbox bound
  the form to the new-comment checkbox.
- If the typo checker failed after the completion instance was created, the
  next DOM mutation attached again and stacked another overlay; a throw in
  `scan()` also skipped `releaseDetached()`.
- The 3-second hide timers of the typo overlay still ran after `destroy()`.
- `start()` did not disconnect an earlier observer, although the comment said
  it was never created twice. `checkbox` without `container` was accepted.

## Original Code

```js
const typoChecker = new window.AiHelperTypoChecker(textarea, {
  checkButton: controls.querySelector(".ai-helper-journal-typo-check-btn"),
  ...
});
setTimeout(() => this.hideOverlay(), 3000);
```

## Fix

`attach()` checks all controls before creating anything and destroys the
completion instance if the typo checker fails. `scan()` reports a failing form
once with `console.error`, skips it afterwards, and the observer always
releases detached forms. The timers check `destroyed`; `start()` disconnects
the previous observer; the completion class throws on `checkbox` without
`container`. Each guard has a test that fails when the guard is removed.

## Root Cause

The AI validated the one input it had seen fail (the textarea) and trusted the
optional-element options it designed itself, whose "not given" fallback is
the page-level lookup. It applied the destroy/ownership checks (CRF-061) to
the async request path but not to timers started by the same class.

## Prevention

When a component accepts an optional element that replaces a global lookup,
the caller must prove the element exists and throw otherwise; "missing" must
never reach the global fallback. A constructor sequence that creates more than
one object wraps the later steps so the earlier objects are destroyed on
failure. List every `setTimeout`/listener a class starts and check each is
covered by `destroy()`.

**Promoted to**: Not yet
