# ADR-073: Re-attach the issue form aids on every re-render of #all_attributes

**Date**: 2026-11-21
**Status**: Accepted

## Context

Changing the project, tracker, status or parent field (and, on the new issue
form only, the category) makes Redmine re-render `#all_attributes`: it copies
modified input values into the response HTML and then runs
`$('#all_attributes').empty()` followed by
`$('#all_attributes').prepend(replacement)`
(`application-legacy.js:727-737` on Redmine 7.0.3; the same sequence exists in
`application.js` of 6.0.0 (`:648-658`), 6.1.0 and 6.1.3 (`:734-735`)). Every element the AI Helper rendered through
`view_issues_form_details_bottom` — the config container, the checkbox
containers, the typo overlay — is therefore replaced by a fresh, unmodified
copy, while the JavaScript initialized everything once at `DOMContentLoaded`
and guarded itself with the page-global flag
`window.aiHelperAutoCompletionInitialized` (in `ai_helper_issue_autocompletion.js`
before this change).
After the first re-render the description completion, the typo check, the
duplicate check and the assignee suggestion stop working (GitHub Issue #573),
because the flag makes every later initialization a no-op.

Measurements drove three additional facts. A `MutationObserver` with
`childList: true`, `subtree: false` on `#all_attributes` fires exactly once per
re-render (2 mutation records, 54 added nodes when changing the tracker), and
by the time its callback runs (a microtask) the response scripts — including
the jsToolBar initialization — have finished, so the existing placement helper
`AiHelperEditorControls.placeAfterEditor` works unchanged. The notes field and
its controls live in `fieldset#add_notes`, outside `#all_attributes`
(`issues/_edit.html.erb:32-45`), so they are never re-rendered; but the notes
controls were rendered inside `#all_attributes` by
`shared/_textarea_overlay.html.erb` and moved below the notes editor by JS at
page display, so every re-render added a second hidden copy with the same ids.
Finally, in-flight requests of released renders kept writing into detached
DOM: the duplicate check wrote results/loading/button state into the removed
container, and the assignee suggestion re-looked up `#issue_assigned_to_id` by
id and could select a user in the new form from a stale panel
(`ai_helper_assignment_suggestion.js` `selectUser`).

## Decision

- `ai_helper_issue_autocompletion.js` is rewritten as the IIFE module
  `AiHelperIssueFormAids` (the shape of `AiHelperJournalEditAids`, ADR-070).
  It observes `#all_attributes` with a `MutationObserver` (`childList: true`,
  no `subtree`); the callback releases detached registrations first and then
  scans for not-yet-registered config containers. Pages without
  `#all_attributes` get no observer. A second `start()` disconnects the
  previous observer.
- One render's aids (description completion, description typo check,
  duplicate check, assignee suggestion) are registered in a `Map` keyed by
  that render's config container `#ai-helper-issue-textarea-overlay`, which is
  re-created per render and appears exactly once per render. A container is
  attached only when it is not registered and not recorded as failed.
  `scan(root)` also accepts a root that is itself a config container.
- The global flag `window.aiHelperAutoCompletionInitialized` is abolished; the
  per-render registry replaces it. `window.aiHelperInstances.autoCompletion`
  keeps pointing at the last attached render's completion; releasing a render
  deletes it when it points at the released completion, before any new attach
  can overwrite it.
- Releasing a detached render calls the existing `destroy()` of the
  completion and the typo checker (which removes the `document` keydown/click
  listeners), aborts the duplicate check's `AbortController` and calls the new
  `AiHelperAssignmentSuggestion#destroy()`, which aborts its in-flight fetch
  and removes link and panel. Aborted or superseded responses write nothing:
  the duplicate check and the suggestion compare their per-request
  controller/`destroyed` state after every `await`, and an `AbortError` is
  neither logged nor rendered.
- If `attach` fails midway (the completion `init()` included — it creates the
  overlay and listeners before `loadSettings()` can throw), the parts created
  so far are destroyed and the error rethrown (an `AggregateError` carrying
  both errors when that destruction fails too). The failure is not swallowed:
  `scan` records the container in a `WeakSet` before attaching and lets the
  error propagate, so it reaches `window.onerror` once (from the observer
  callback) and placement callbacks cannot repeat it; a later render has a new
  container and is attached again. `start()` sets up the notes aids and the
  observer even when the description attach fails, then rethrows. A missing
  `data-config` (or `data-assignment-config` when the assignee select exists)
  is a rendering bug and throws instead of being read as `{}`.
- A registry entry leaves the registry before it is released, so a `destroy()`
  that throws surfaces once; the observer callback scans for the new render
  even when the release threw. Because a released entry is never visited
  again, the release runs every part (completion, typo checker, duplicate-check
  abort, assignee suggestion) even when an earlier one throws, then rethrows
  (an `AggregateError` when several parts failed). Each entry carries a `released` flag, so the
  duplicate-check button listener of an entry whose attach failed does nothing
  instead of starting a request nobody can abort, and a second click aborts
  the previous duplicate-check request.
- The notes checkbox container and the notes typo control panel move from
  `shared/_textarea_overlay.html.erb` to the new partial
  `ai_helper/issues/_notes_controls.html.erb`, rendered by
  `view_issues_edit_notes_bottom` inside `fieldset#add_notes` (outside
  `#all_attributes`), guarded by `PermissionChecker.module_enabled?` and
  `issue.attributes_editable?` — the same conditions under which they were
  rendered before. The hook is called only from `issues/_edit.html.erb`, so
  the old `@issue.persisted?` check is implied by where the partial renders.
  The project is judged as `@project || issue.project`, exactly like the config
  container partial: the notes aids read their settings from that container, so
  after a failed update that moved the issue to another project (where
  `issue.project` is already the target) both partials still agree. `view_issues_edit_notes_bottom` receives both partials
  (`ai_helper/issues/form`, `ai_helper/issues/notes_controls`) in one
  `render_on` call, because a second `render_on` for the same hook overwrites
  the first. The notes completion and notes typo check are attached once at
  page display (`attachNotes`), reading their settings from the page-level
  config container, and are not part of the per-render registry.
- Server-side code (controllers, agents, endpoints) is unchanged. HTML is
  built only in ERB; the JS only moves and reads elements the ERB rendered.

## Consequences

- All four description-area features survive any number of re-renders with
  exactly one set of controls, and a check button click sends exactly one
  request (verified for five consecutive re-renders).
- Re-renders no longer duplicate the notes controls (FR-004). On the global
  New issue page (`/issues/new`, no `@project`), switching to a project with
  the module disabled renders no hook output, which releases everything and
  hides the features until an enabled render returns (SC-003). In the
  project-scoped new form and the edit form `_textarea_overlay.html.erb` keeps
  judging by `@project` (the page-load project), so those features stay after
  a project switch (SF-047); the notes aids likewise keep the page-load
  project's endpoint.
- In-flight duplicate-check and assignee-suggestion requests of a released
  render can no longer write into the new form. The description completion's
  on/off state carries over (FR-006): before a render is released its state is
  recorded, and the next render's completion gets it back through
  `restoreEnabled()` after `init()`, without writing storage. The
  `localStorage` key (`aiHelperAutoCompletion_<userId>`) that `init()` reads
  cannot carry it, because the description and the notes toggles both write
  that one key; relying on it would let a notes toggle change flip the
  description toggle on the next re-render. The recorded state survives a
  render without a description editor.
- The unused notes typo control panel is no longer rendered on the new-issue
  form, where it had no function.
- The observer runs on every direct-child mutation of `#all_attributes`,
  including the module's own container placements; each callback does only
  the registry check and one `querySelectorAll`, and registered containers
  make those callbacks no-ops.

## Alternatives Considered

- Overwrite Redmine's global `replaceIssueFormWith`: patching a core function
  couples the plugin to one Redmine version's internals, the same reason
  ADR-070 rejected a JS hook after `edit.js.erb`.
- Use jQuery's `ajaxComplete`: jQuery is not allowed in this plugin's
  JavaScript (Constitution IV).
- Observe `document.body` with `subtree: true`: the completion and typo
  overlays appearing would trigger the callback every time; the form UI lives
  only inside `#all_attributes`.
- Keep initializing only at `DOMContentLoaded`: that is the bug itself.
- Render the notes controls inside `#all_attributes` and remove the
  duplicates with JS: server-rendered markup would be deleted by JS and the
  ids would be duplicated until the removal ran.
- Give the notes controls their own `data-config`: would also show the notes
  features to users who may write notes but not edit attributes, changing
  display conditions outside this scope (YAGNI).
