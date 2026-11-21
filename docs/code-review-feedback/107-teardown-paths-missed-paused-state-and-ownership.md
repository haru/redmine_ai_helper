# CRF-107: New teardown paths missed paused state, request ownership and the project the siblings use

**Date**: 2026-11-21
**Source**: Local AI review (speckit-review-run, 6 agents)
**Feature**: branch `bugfix/088-fix-issue-form-rerender`
**Files**: assets/javascripts/typo_checker/ai_helper_typo_checker.js, assets/javascripts/autocompletion/ai_helper_assignment_suggestion.js, assets/javascripts/autocompletion/ai_helper_issue_autocompletion.js, app/views/ai_helper/issues/_notes_controls.html.erb
**Category**: edge-case
**Related**: CRF-049, CRF-061, CRF-098

## Feedback

- Releasing a render now destroys the description typo checker, but `destroy()` never resumed the autocompletions the checker had paused while its overlay was shown, so notes completion stayed off until the checkbox was toggled.
- A second duplicate-check click replaced the abort controller without aborting the first request.
- `AiHelperAssignmentSuggestion#init()/open()` still worked on a destroyed instance, and `close()` left the aborted controller as the owner token, forcing three overlapping guards.
- `_notes_controls.html.erb` judged `module_enabled?` by `issue.project`, while the config container it depends on uses `@project || @issue.project`; after a failed update that moved the issue, only one of the two rendered.

## Original Code

```ruby
module_enabled?(project: issue.project) && issue.attributes_editable?
```

## Fix

`destroy()` resumes the paused completions when the overlay is active; the previous request is aborted before a new one starts; destroyed instances throw from `init()/open()` and `close()` clears the token; the notes partial uses `@project || issue.project`, with a functional test driving a failed update that moves the issue.

## Root Cause

The AI added `destroy()` calls to an existing object that had never been destroyed before, without reading what state the object had changed elsewhere (`disableAutocompletion`). It copied the project expression from the spec's wording ("the saved issue's project") instead of reading the sibling partial it depends on, and it did not trace the failed-update render path.

## Prevention

Before a new caller starts destroying an existing object, read every side effect of that object's lifetime (state it paused, flags it set on other instances) and undo them in `destroy()`. When two partials share one config, copy the sibling's project/condition expression and test a render where the page-load and the model values differ. A request owner token is released by the same method that aborts the request.

**Promoted to**: Not yet
