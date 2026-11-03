/**
 * AI Helper aids (typo check, auto-completion) for journal edit forms.
 *
 * Redmine inserts a journal's edit form with jQuery after the user clicks
 * "Edit" (journals/edit.js.erb), so the forms do not exist at DOMContentLoaded.
 * This script watches #history with a MutationObserver and attaches one
 * AiHelperTypoChecker (and, later, one AiHelperAutoCompletion) per edit form,
 * driving the elements rendered by the
 * ai_helper/journals/_notes_form_controls.html.erb partial.
 */
const AiHelperJournalEditAids = (() => {
  /** @type {Map<HTMLFormElement, object>} Registry of live edit-form aids (`{autoCompletion, typoChecker}`), keyed by the form element. */
  const registry = new Map();

  /** @type {MutationObserver|null} The observer watching #history, kept so it is never created twice. */
  let observer = null;

  /**
   * Attach the aids to one journal edit form, identified by its
   * `.ai-helper-journal-edit-controls` container. Malformed configuration and
   * a missing textarea are errors, not skippable conditions.
   * @param {HTMLElement} controls - The `.ai-helper-journal-edit-controls` element inside the form.
   * @returns {object|null} The registry entry `{autoCompletion, typoChecker}` for the form, or the existing entry when already attached.
   *
   * `AiHelperTypoChecker` is a global defined in ai_helper_typo_checker.js.
   */
  function attach(controls) {
    const form = controls.closest("form");
    const config = JSON.parse(controls.dataset.config);

    if (registry.has(form)) {
      return registry.get(form);
    }

    const textarea = form.querySelector(`#${config.textareaId}`);
    if (!textarea) {
      throw new Error(`ai_helper: textarea #${config.textareaId} not found inside form #${form.id}`);
    }

    const autoCompletion = new window.AiHelperAutoCompletion(textarea, {
      contextType: "note",
      endpoint: config.completionEndpoint,
      userId: config.userId,
      debounceDelay: config.debounceDelay,
      minLength: config.minLength,
      suggestionColor: config.suggestionColor,
      journalId: config.journalId,
      checkbox: controls.querySelector(".ai-helper-journal-autocompletion-toggle"),
      container: controls,
      labels: config.completionLabels,
    });
    autoCompletion.init();

    const typoChecker = new window.AiHelperTypoChecker(textarea, {
      endpoint: config.typoEndpoint,
      labels: config.typoLabels,
      checkButton: controls.querySelector(".ai-helper-journal-typo-check-btn"),
      controlPanel: controls.querySelector(".ai-helper-journal-typo-control-panel"),
      // Pausing completion while the typo overlay is shown applies to this
      // form's own completion only
      autoCompletion: autoCompletion,
    });
    typoChecker.init();

    const entry = { autoCompletion, typoChecker };
    registry.set(form, entry);

    // Place the controls after the editor and show them
    window.AiHelperEditorControls.placeAfterEditor(textarea, controls);

    return entry;
  }

  /**
   * Attach every not-yet-attached controls container within `root`.
   * @param {Element|Document} root - The element to search (`#history` or the document).
   */
  function scan(root) {
    // querySelectorAll skips the root itself (CRF-049), so a container passed
    // directly as root is handled too
    if (root instanceof Element && root.matches(".ai-helper-journal-edit-controls")) {
      attach(root);
    }
    root.querySelectorAll(".ai-helper-journal-edit-controls").forEach((controls) => {
      attach(controls);
    });
  }

  /**
   * Release the aids of registered forms that have left the document (cancel,
   * save, or an ancestor removal).
   */
  function releaseDetached() {
    // isConnected also catches the removal of an ancestor (#change-<id> is
    // deleted with its whole subtree when a journal becomes empty on save)
    registry.forEach((entry, form) => {
      if (!form.isConnected) {
        entry.typoChecker.destroy();
        entry.autoCompletion.destroy();
        registry.delete(form);
      }
    });
  }

  /**
   * Scan the existing edit forms in #history and observe it so forms Redmine
   * inserts (or removes) later are picked up. Does nothing outside a page
   * with #history.
   */
  function start() {
    const history = document.getElementById("history");
    if (!history) {
      return;
    }

    scan(history);

    observer = new MutationObserver(() => {
      scan(history);
      releaseDetached();
    });
    observer.observe(history, { childList: true, subtree: true });
  }

  /**
   * @param {HTMLFormElement} form - The journal edit form.
   * @returns {object|undefined} The registry entry for the form, if attached.
   */
  function entryFor(form) {
    return registry.get(form);
  }

  return { attach, scan, releaseDetached, start, entryFor };
})();

window.AiHelperJournalEditAids = AiHelperJournalEditAids;

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => {
    window.AiHelperJournalEditAids.start();
  });
} else {
  window.AiHelperJournalEditAids.start();
}
