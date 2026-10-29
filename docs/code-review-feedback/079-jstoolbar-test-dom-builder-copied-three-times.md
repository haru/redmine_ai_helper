# CRF-079: The jsToolBar DOM builder was copied into three test files

**Date**: 2026-10-29
**Source**: Local AI review (speckit-review-run, simplify, code and tests agents)
**Feature**: branch `bugfix/541-preview-control-position` (specs/082-fix-preview-control-position)
**Files**: test/javascript/support/jst_editor.js, test/javascript/shared/ai_helper_editor_controls.test.js, test/javascript/autocompletion/ai_helper_issue_autocompletion.test.js, test/javascript/autocompletion/ai_helper_wiki_autocompletion.test.js
**Category**: readability
**Related**: CRF-034, CRF-042

## Feedback

The same markup (`div.jstBlock > (div.jstTabs.tabs + div.jstEditor > (textarea + div#preview_<id>.wiki.wiki-preview.hidden))`) was built three times: `buildJstEditor` in the helper test, the inner `buildEditor` of `createJstIssueDOM`, and inline in `createJstWikiDOM`. A change in Redmine's jsToolBar markup would need the same edit in three places. Smaller points from the same review: the new tests called `dom.form.remove()` although `afterEach` already removes the tracked forms; the issue test looked up `#issue_description_and_toolbar` with `getElementById` although the builder had created it; and the helper test repeated `await loadScript(...)` in each of its five tests.

## Original Code

```js
// three copies of
const block = document.createElement("div"); block.className = "jstBlock";
const tabs = ...; const editor = ...; const preview = ...;
```

## Fix

`test/javascript/support/jst_editor.js` exports `createJstEditor(textareaId)` with a JSDoc that cites the source markup (jstoolbar.js lines 25-36 and 64-65), like `support/dashboard_detail_pane.js`. All three tests use it and wrap the returned block in their own parent. The redundant `remove()` calls were deleted, the builder returns `descWrapper`, and `loadScript` moved to `beforeEach`.

## Root Cause

The builder was written first in the helper test, then re-created for each new test file instead of moved to `test/javascript/support/`, where the project already keeps shared DOM builders. The constitution's DRY rule (extract at three occurrences) was applied to the production code (three insertion sites became one helper) but not to the test fixtures written in the same change. The tracked-node cleanup was added after the first tests, and the earlier `remove()` calls were not revisited.

## Prevention

When a test fixture (a DOM builder, a fake) is needed in a second test file, check `test/javascript/support/` first; at the third copy extract it there with a JSDoc citing the production markup. When `afterEach` removes the nodes a builder tracks, tests do not also call `remove()` on them.

**Promoted to**: Not yet
