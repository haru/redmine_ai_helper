# ADR-070: Attach typo check and auto-completion to comment edit forms through a hook and a MutationObserver

**Date**: 2026-11-03
**Status**: Accepted

## Context

Redmine inserts a posted comment's edit form with jQuery after the user clicks
"Edit" (`journals/edit.js.erb`), so the form does not exist at
`DOMContentLoaded`. The existing typo check and auto-completion UI is rendered
only by `view_issues_form_details_bottom` (the issue update form), so a user who
may edit notes but has no issue update form gets nothing. The two JS classes
also look their elements up by fixed ids (`issue_description`, `issue_notes`,
`content_text`), which cannot address several edit forms on one page
(`journal_<id>_notes`). ADR-025 lists `DOMContentLoaded` and an explicit
initialisation call as the ways to start a feature.

## Decision

- Register the partial `ai_helper/journals/_notes_form_controls.html.erb` on
  Redmine's `view_journals_notes_form_after_notes` hook. It renders one
  `.ai-helper-journal-edit-controls` container inside the edit form (checkbox,
  typo check link, control panel, accept/reject button templates, `data-config`),
  guarded by `PermissionChecker.module_enabled?`. The checkbox id contains the
  journal id; the other elements are found by class within the container.
- `ai_helper_journal_edit_aids.js` observes `#history` with a
  `MutationObserver` (`childList`, `subtree`). Each change attaches one
  `AiHelperAutoCompletion` and one `AiHelperTypoChecker` per not-yet-registered
  form (a `Map` keyed by the form element) and releases registered forms whose
  `isConnected` is false by calling `destroy()` on both.
- `attach()` checks the textarea and the three controls (checkbox, check
  button, control panel) before creating anything and throws when one is
  missing, because the components would otherwise fall back to the page-level
  new-comment controls. If the typo checker fails after the completion instance
  was created, the completion instance is destroyed. `scan()` reports a form
  whose attach failed once with `console.error` and never retries it, so one
  broken form neither repeats on every mutation nor blocks releasing the
  detached forms. `start()` disconnects a previous observer.
- `AiHelperAutoCompletion` and `AiHelperTypoChecker` accept optional elements
  (`checkbox`/`container`, `checkButton`/`controlPanel`/`autoCompletion`) that
  replace the id lookups; without them behaviour is unchanged.
  `AiHelperTypoChecker#destroy()` removes its `document` and textarea listeners
  and makes late `checkTypos` responses no-ops.
- Edit-form completion is not registered in `window.aiHelperInstances`; a typo
  check pauses only its own form's completion.

## Consequences

- The UI appears whenever the edit form appears (FR-002), independent of the
  issue update form.
- Several forms, cancel/reopen and save/reopen work without duplicate controls
  or leaked listeners. Removing an ancestor (`#change-<id>`) is covered because
  release checks `isConnected`, not the removed nodes.
- Adds a third way to start a feature next to ADR-025's two.
- The two existing classes gain optional parameters, so their option surface
  grows.

## Alternatives Considered

- Clone the `_textarea_overlay.html.erb` elements with JS: the source does not
  exist on pages without the issue update form, and it builds HTML in JS.
- Fetch the UI HTML from a dedicated endpoint when the form opens: one extra
  request where the hook is enough.
- Initialise from a JS hook after `edit.js.erb`: `edit.js.erb` has no
  after-call hook (only `update.js.erb` has).
- Put an inline script in the partial: contradicts ADR-025 (no inline script in
  ERB).
- Observe `document.body`: journals exist only under `#history`.
- Write a new class for the edit form: duplicates about 1,100 lines of display,
  accept and reject code (DRY, ADR-026).
- Add `journal_<id>_notes` to the id maps by regular expression: the control
  panel and button ids are dynamic as well and cannot be expressed in the maps.
