/**
 * AI Helper aids (typo check, auto-completion) for journal edit forms.
 *
 * Redmine inserts a journal's edit form with jQuery after the user clicks
 * "Edit" (journals/edit.js.erb), so the forms do not exist at DOMContentLoaded.
 * This script watches #history with a MutationObserver and attaches one
 * AiHelperAutoCompletion and one AiHelperTypoChecker per edit form, driving
 * the elements rendered by the
 * ai_helper/journals/_notes_form_controls.html.erb partial.
 */
const AiHelperJournalEditAids = (() => {
  /** @type {Map<HTMLFormElement, object>} Registry of live edit-form aids (`{autoCompletion, typoChecker}`), keyed by the form element. */
  const registry = new Map();

  /** @type {WeakSet<HTMLFormElement>} Forms whose attach failed; reported once and never retried. */
  const failedForms = new WeakSet();

  /** @type {MutationObserver|null} The observer watching #history; start() disconnects it before creating a new one. */
  let observer = null;

  /**
   * Find a control inside the container or throw. A missing control is a
   * rendering error: letting the components fall back to their page-level
   * lookups would bind this form to the new-comment field's controls.
   * @param {HTMLElement} controls - The `.ai-helper-journal-edit-controls` element.
   * @param {string} selector - The class selector of the control.
   * @returns {HTMLElement} The control element.
   */
  function requireControl(controls, selector) {
    const element = controls.querySelector(selector);
    if (!element) {
      throw new Error(`ai_helper: ${selector} not found inside the journal edit controls of form #${controls.closest("form").id}`);
    }
    return element;
  }

  /**
   * Attach the aids to one journal edit form, identified by its
   * `.ai-helper-journal-edit-controls` container. Malformed configuration, a
   * missing textarea and a missing control are errors, not skippable
   * conditions; nothing is created before all of them have been checked.
   * @param {HTMLElement} controls - The `.ai-helper-journal-edit-controls` element inside the form.
   * @returns {object} The registry entry `{autoCompletion, typoChecker}` for the form, or the existing entry when already attached.
   *
   * `AiHelperTypoChecker` is a global defined in ai_helper_typo_checker.js.
   */
  function attach(controls) {
    const form = controls.closest("form");
    if (!form) {
      throw new Error("ai_helper: the journal edit controls are not inside a form");
    }

    if (registry.has(form)) {
      return registry.get(form);
    }

    const config = JSON.parse(controls.dataset.config);

    const textarea = form.querySelector(`#${config.textareaId}`);
    if (!textarea) {
      throw new Error(`ai_helper: textarea #${config.textareaId} not found inside form #${form.id}`);
    }
    const checkbox = requireControl(controls, ".ai-helper-journal-autocompletion-toggle");
    const checkButton = requireControl(controls, ".ai-helper-journal-typo-check-btn");
    const controlPanel = requireControl(controls, ".ai-helper-journal-typo-control-panel");

    const autoCompletion = new window.AiHelperAutoCompletion(textarea, {
      contextType: "note",
      endpoint: config.completionEndpoint,
      userId: config.userId,
      debounceDelay: config.debounceDelay,
      minLength: config.minLength,
      suggestionColor: config.suggestionColor,
      journalId: config.journalId,
      checkbox: checkbox,
      container: controls,
      labels: config.completionLabels,
    });
    autoCompletion.init();

    try {
      const typoChecker = new window.AiHelperTypoChecker(textarea, {
        endpoint: config.typoEndpoint,
        labels: config.typoLabels,
        checkButton: checkButton,
        controlPanel: controlPanel,
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
    } catch (error) {
      // Do not leave a half-built form behind: its completion overlay and
      // listeners would otherwise be stacked again by the next attach
      autoCompletion.destroy();
      throw error;
    }
  }

  /**
   * Attach every not-yet-attached controls container within `root`. A form
   * that fails to attach is reported once with console.error and skipped from
   * then on, so one broken form neither repeats on every DOM mutation nor
   * blocks the others.
   * @param {Element|Document} root - The element to search (`#history` or the document).
   */
  function scan(root) {
    // querySelectorAll skips the root itself (CRF-049), so a container passed
    // directly as root is handled too
    const containers = Array.from(root.querySelectorAll(".ai-helper-journal-edit-controls"));
    if (root instanceof Element && root.matches(".ai-helper-journal-edit-controls")) {
      containers.unshift(root);
    }
    containers.forEach((controls) => {
      const form = controls.closest("form");
      if (failedForms.has(form)) {
        return;
      }
      try {
        attach(controls);
      } catch (error) {
        if (form) {
          failedForms.add(form);
        }
        console.error(`ai_helper: failed to attach the journal edit aids to form #${form.id}`, error);
      }
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

    // A second start() must not leave the first observer running
    if (observer) {
      observer.disconnect();
    }
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
