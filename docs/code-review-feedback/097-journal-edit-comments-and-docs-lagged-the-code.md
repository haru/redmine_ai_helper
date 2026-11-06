# CRF-097: Comments, JSDoc, wiki pages and an ADR lagged the journal edit code

**Date**: 2026-11-03
**Source**: Local AI review (speckit-review-run: comments)
**Feature**: branch `feature/085-journal-edit-typo-completion`
**Files**: assets/javascripts/autocompletion/ai_helper_journal_edit_aids.js, assets/javascripts/autocompletion/ai_helper_auto_completion.js, assets/javascripts/typo_checker/ai_helper_typo_checker.js, app/views/ai_helper/journals/_notes_form_controls.html.erb, lib/redmine_ai_helper/util/completion_journal_resolver.rb, docs/adr/070-journal-edit-form-aids-attachment.md, wiki/sources.md, wiki/pages/issue-ai-features.md, wiki/pages/inline-completion-request-flow.md
**Category**: doc-comment
**Related**: CRF-092, CRF-005, CRF-007

## Feedback

- A file header still said "(and, later, one AiHelperAutoCompletion)"; the
  constructors' JSDoc omitted the new options; `disableAutocompletion`,
  `buildDefaultRequestBody` and `@returns {object|null}` no longer matched.
- The resolver comment said both checks used the requesting user, but the
  visibility check used `User.current`.
- ADR-070 said every element id contains the journal id; only the checkbox's
  does. The ERB comment named one of the two partials that carry the templates.
- The wiki sections cited ADRs only: no source id in `wiki/sources.md`, and
  `updated`/`sources` were not bumped (`wiki/SCHEMA.md`).

## Original Code

```js
 * AiHelperTypoChecker (and, later, one AiHelperAutoCompletion) per edit form
```

## Fix

Comments, JSDoc, ERB comment and ADR-070 corrected; S061 registered in
`wiki/sources.md`, cited in both pages, frontmatter updated; the resolver
comment is true because it now uses `Journal.visible(user)`.

## Root Cause

The files were written step by step across user stories; the comments written
for an earlier step were not revisited when the later step landed, and the
wiki rules in `wiki/SCHEMA.md` were not consulted.

## Prevention

Before finishing a feature, grep each new comment/JSDoc for "later", "TODO",
"only" and "every", and verify each claim against the final code. A wiki
section needs a registered source id and bumped frontmatter in the same change.

**Promoted to**: Not yet
