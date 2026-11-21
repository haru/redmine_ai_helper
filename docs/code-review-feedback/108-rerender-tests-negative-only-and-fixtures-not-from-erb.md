# CRF-108: Re-render tests had negative-only assertions and fixtures that did not follow the ERB

**Date**: 2026-11-21
**Source**: Local AI review (speckit-review-run, 6 agents)
**Feature**: branch `bugfix/088-fix-issue-form-rerender`
**Files**: test/functional/ai_helper_view_hook_test.rb, test/javascript/autocompletion/ai_helper_issue_autocompletion.test.js
**Category**: test-gap
**Related**: CRF-033, CRF-042, CRF-051, CRF-077

## Feedback

- The issues/new.js and issues/edit.js tests only used `assert_not_includes`, so they passed even if the response held no form.
- The notes-move test passed without a move: the fixture put the notes container right below the editor, and Redmine's real `fieldset#add_notes` has the toolbar script, private-notes checkbox and reply fieldset in between.
- The "collapsed description" scenario was built on a wrong premise: a collapsed description keeps its textarea in a hidden span; it is absent only when `safe_attribute?('description')` is false. The hidden-editor re-render was untested.
- The rollback test did not assert that the global reference was cleared; duplicated config builders and fixtures made fixtures drift.

## Original Code

```ruby
assert_not_includes @response.body, "ai-helper-notes-checkbox-container"
```

## Fix

Positive controls (`replaceIssueFormWith`, the overlay id) were added; the fixtures now follow `_edit.html.erb` / `_form.html.erb` order with a pre-assertion that the container is not yet at the target; a hidden-editor re-render test and the global-reference assertion were added; config builders and the fetch stub were consolidated (`support/fetch_stub.js`).

## Root Cause

The tests were written from the implementation's view of the DOM instead of transcribed from the ERB, and the "collapsed" wording came from a comment, not from reading `_form.html.erb:32-41`. The CRF-033/042/077 rules existed but were not consulted when writing the new fixtures.

## Prevention

Open the ERB and copy its element order before writing a fixture; pre-assert that a moved element is not at the target; pair every negative assertion on a response with a positive assertion on the region searched; check a fixture premise against the template's `if`.

**Promoted to**: Not yet
