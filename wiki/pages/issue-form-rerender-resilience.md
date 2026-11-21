---
title: Issue Form Re-render Resilience
type: component
sources: [S064]
updated: 2026-11-21
---

# Issue Form Re-render Resilience

How the issue form's AI Helper aids survive Redmine re-rendering the form.
Split from [Issue AI Features](./issue-ai-features.md).

## Mechanism
- Changing the project, tracker, status or parent field (and, on the new issue
  form only, the category) makes Redmine empty `#all_attributes` and prepend a
  fresh form, so every element rendered by `view_issues_form_details_bottom` is
  replaced (S064, ADR-073).
- `AiHelperIssueFormAids` observes `#all_attributes` with a `MutationObserver`
  (`childList`, no `subtree`). Each callback releases the renders that left the
  document, then attaches the aids of every not-yet-registered config container
  `#ai-helper-issue-textarea-overlay` (one per render; the registry key).
- One entry holds the description completion, typo checker, duplicate-check
  request and assignee suggestion. Releasing it destroys each part, aborts the
  in-flight requests and clears `window.aiHelperInstances.autoCompletion` when
  it points at the released completion (S064).

## Failure handling
- An attach failure is not swallowed: the parts built so far are released and
  the error is rethrown (an `AggregateError` when releasing fails too). The
  container is recorded before it is attached, so the error surfaces once per
  render; the next render is attached again. `start()` still attaches the notes
  aids and the observer, then rethrows (S064).
- A missing `data-config`, or `data-assignment-config` when the assignee select
  exists, throws. A persisted issue's notes editor without notes controls
  throws too.
- A second duplicate-check click aborts the first request; a released entry's
  button does nothing. A destroyed typo checker resumes the completions it had
  paused (S064).

## Notes aids and conditions
- The notes controls render in `view_issues_edit_notes_bottom`, outside
  `#all_attributes`, judged by `@project || issue.project` like the config
  container. The notes aids attach once per page and are not re-attached.
- Only on the global `/issues/new` page does a project switch re-judge the
  module-enabled condition; the edit form and the project-scoped new form keep
  the page-load project (S064).
