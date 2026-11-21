/**
 * AI Helper aids for the issue form: description-field auto-completion,
 * description typo check, duplicate check, and assignee suggestion, plus the
 * notes-field aids of the edit form.
 *
 * Redmine re-renders `#all_attributes` whenever the user changes the project,
 * tracker, status or parent issue field (and, on the new issue form, the
 * category) via updateIssueFrom / replaceIssueFormWith, so the containers
 * rendered by view_issues_form_details_bottom are replaced by fresh elements.
 * This module watches #all_attributes with a MutationObserver and attaches
 * one set of aids per render, keyed by the render's config container
 * (#ai-helper-issue-textarea-overlay), releasing the aids of renders that
 * left the document. Every render is initialized on its own (ADR-073).
 *
 * The registry/observer skeleton mirrors ai_helper_journal_edit_aids.js
 * (ADR-070); keep the two in sync when changing either.
 */
const AiHelperIssueFormAids = (() => {
  /**
   * The aids of one render. `released` turns true when the render's aids were
   * torn down, so a listener that outlived the teardown can tell.
   * @typedef {object} IssueFormAidsEntry
   * @property {AiHelperAutoCompletion|null} autoCompletion The description completion.
   * @property {AiHelperTypoChecker|null} typoChecker The description typo checker.
   * @property {AbortController|null} duplicateCheckAbort Controller of the duplicate-check request in flight.
   * @property {AiHelperAssignmentSuggestion|null} assignmentSuggestion The assignee suggestion.
   * @property {boolean} released True once releaseEntry() ran for this entry.
   */

  /** @type {Map<HTMLElement, IssueFormAidsEntry>} Per-render aid entries, keyed by the render's config container. */
  const registry = new Map();

  /** @type {WeakSet<HTMLElement>} Config containers whose attach is running or failed; never retried. */
  const failedOverlays = new WeakSet();

  /** @type {MutationObserver|null} The observer watching #all_attributes; start() disconnects it before creating a new one. */
  let observer = null;

  /** @type {boolean} The notes-field aids are created once at page display, never per render (R-004). */
  let notesAttached = false;

  /**
   * @type {boolean|null} The on/off state of the last released description
   * completion, restored on the next render's completion; null until a render
   * with a description completion was released. It is not cleared by a
   * render without one, so the state survives such a render too. The
   * localStorage key cannot carry it: the notes toggle writes the same key
   * (FR-006).
   */
  let descriptionEnabled = null;

  /**
   * Parse a JSON data attribute of a config container. A missing attribute is
   * a rendering bug, not an empty config, so it throws.
   * @param {HTMLElement} element The config container.
   * @param {string} key The dataset key (`config`, `assignmentConfig`).
   * @param {string} attributeName The attribute as written in the markup, for the message.
   * @returns {object} The parsed config.
   * @throws {Error} When the attribute is missing.
   */
  function readConfig(element, key, attributeName) {
    const raw = element.dataset[key];
    if (raw === undefined) {
      throw new Error(`#${element.id} has no ${attributeName} attribute`);
    }
    return JSON.parse(raw);
  }

  /**
   * Publish an instance on window.aiHelperInstances.
   * @param {string} name The property name.
   * @param {object} instance The instance to publish.
   */
  function publishInstance(name, instance) {
    if (!window.aiHelperInstances) {
      window.aiHelperInstances = {};
    }
    window.aiHelperInstances[name] = instance;
  }

  /**
   * Build the AiHelperAutoCompletion options shared by the description and
   * the notes completion.
   * @param {object} config Parsed overlay config (`dataset.config`).
   * @param {object} specifics What differs per field.
   * @param {string} specifics.contextType `description` or `note`.
   * @param {string} specifics.endpoint The completion endpoint.
   * @param {string} specifics.enabledTooltip Tooltip label while enabled.
   * @param {string} specifics.disabledTooltip Tooltip label while disabled.
   * @returns {object} The options for `new AiHelperAutoCompletion(textarea, options)`.
   */
  function completionOptions(config, { contextType, endpoint, enabledTooltip, disabledTooltip, ...extra }) {
    return {
      contextType,
      endpoint,
      userId: config.userId,
      debounceDelay: config.debounceDelay,
      minLength: config.minLength,
      suggestionColor: config.suggestionColor,
      ...extra,
      // I18n labels
      labels: {
        commonToggleLabel: config.labels.commonToggleLabel,
        loading: config.labels.loading,
        noSuggestions: config.labels.noSuggestions,
        acceptSuggestion: config.labels.acceptSuggestion,
        dismiss: config.labels.dismiss,
        enabledTooltip,
        disabledTooltip
      }
    };
  }

  /**
   * Release every part of a per-render entry and clear
   * window.aiHelperInstances.autoCompletion when it points at the released
   * completion. Used both when a render leaves the document and when attach
   * fails midway. The parts are independent, so every part is released even
   * when another one throws; the entry has already left the registry, and a
   * part skipped here would never be released. The error is rethrown after
   * all parts ran: as is when one part failed, as an AggregateError when
   * several did.
   * @param {IssueFormAidsEntry} entry The entry to release.
   * @throws {Error|AggregateError} When releasing one or more parts failed.
   */
  function releaseEntry(entry) {
    entry.released = true;
    if (window.aiHelperInstances && window.aiHelperInstances.autoCompletion === entry.autoCompletion) {
      delete window.aiHelperInstances.autoCompletion;
    }
    const errors = [];
    const releasePart = (release) => {
      try {
        release();
      } catch (error) {
        errors.push(error);
      }
    };
    if (entry.autoCompletion) {
      releasePart(() => entry.autoCompletion.destroy());
    }
    if (entry.typoChecker) {
      releasePart(() => entry.typoChecker.destroy());
    }
    if (entry.duplicateCheckAbort) {
      const controller = entry.duplicateCheckAbort;
      entry.duplicateCheckAbort = null;
      releasePart(() => controller.abort());
    }
    if (entry.assignmentSuggestion) {
      releasePart(() => entry.assignmentSuggestion.destroy());
    }
    if (errors.length === 1) {
      throw errors[0];
    }
    if (errors.length > 1) {
      throw new AggregateError(errors, `Failed to release ${errors.length} parts of the issue form aids (${errors.map((e) => e.message).join('; ')})`);
    }
  }

  /**
   * The message of a non-ok duplicate-check response: the server's `error`
   * for a JSON body, otherwise the HTTP status (an HTML error page has no
   * JSON to read).
   * @param {Response} response The non-ok response.
   * @returns {Promise<string>} The message to show.
   */
  async function duplicateCheckErrorMessage(response) {
    if ((response.headers.get('Content-Type') || '').includes('application/json')) {
      const errorData = await response.json();
      return errorData.error || 'Unknown error';
    }
    return `HTTP ${response.status} ${response.statusText}`;
  }

  /**
   * Run the duplicate-check request for the current subject/description and
   * render the results (or an error) into the results container. The request
   * belongs to the render's entry: when the render is released mid-request,
   * or a newer click supersedes it, the controller is aborted and the settled
   * response touches nothing (FR-007, CRF-061).
   * @param {IssueFormAidsEntry} entry The registry entry owning this request.
   * @param {object} config Parsed overlay config (`dataset.config`).
   * @param {HTMLElement} descriptionTextarea The issue description textarea.
   */
  async function runDuplicateCheck(entry, config, descriptionTextarea) {
    // The click listener outlives a released render when attach failed after
    // it was added; such a request could never be aborted
    if (entry.released) {
      return;
    }

    const subjectInput = document.getElementById('issue_subject');
    const duplicateCheckResults = document.getElementById('ai-helper-duplicate-check-results');
    const duplicateCheckLoading = document.getElementById('ai-helper-duplicate-check-loading');
    const duplicateCheckBtn = document.getElementById('ai-helper-duplicate-check-btn');

    const subject = subjectInput ? subjectInput.value : '';
    const description = descriptionTextarea ? descriptionTextarea.value : '';

    if (!subject.trim() && !description.trim()) {
      alert(config.duplicateCheckLabels.emptyContent);
      return;
    }

    // The disabled class is only styling: a second click starts a new request
    if (entry.duplicateCheckAbort) {
      entry.duplicateCheckAbort.abort();
    }
    const controller = new AbortController();
    entry.duplicateCheckAbort = controller;

    // Show loading, hide results
    duplicateCheckLoading.style.display = 'flex';
    duplicateCheckResults.style.display = 'none';
    duplicateCheckBtn.classList.add('disabled');

    try {
      const token = document.querySelector('meta[name="csrf-token"]').content;
      const response = await fetch(config.duplicateCheckEndpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': token
        },
        body: JSON.stringify({subject: subject, description: description}),
        signal: controller.signal
      });

      if (!response.ok) {
        throw new Error(await duplicateCheckErrorMessage(response));
      }

      const html = await response.text();
      // The render was released, or a newer click superseded this request
      if (entry.duplicateCheckAbort !== controller) {
        return;
      }
      duplicateCheckResults.innerHTML = html;
      duplicateCheckResults.style.display = 'block';
    } catch (error) {
      // An aborted request (released render or superseded click) no longer
      // owns the entry; it must neither be logged nor rendered as an error of
      // the current form (CRF-061)
      if (entry.duplicateCheckAbort !== controller) {
        return;
      }
      console.error('Duplicate check error:', error);
      duplicateCheckResults.innerHTML = '';
      const errorParagraph = document.createElement('p');
      errorParagraph.className = 'ai-helper-error';
      errorParagraph.textContent = error.message;
      duplicateCheckResults.appendChild(errorParagraph);
      duplicateCheckResults.style.display = 'block';
    } finally {
      if (entry.duplicateCheckAbort === controller) {
        duplicateCheckLoading.style.display = 'none';
        duplicateCheckBtn.classList.remove('disabled');
      }
    }
  }

  /**
   * Place the duplicate-check container below the description checkbox and
   * wire up its trigger button. The button's request belongs to `entry`, so
   * a released render aborts it.
   * @param {IssueFormAidsEntry} entry The registry entry for this render.
   * @param {HTMLElement} duplicateCheckContainer The render's duplicate-check container.
   * @param {object} config Parsed overlay config (`dataset.config`).
   * @param {HTMLElement} descriptionTextarea The issue description textarea.
   */
  function initializeDuplicateCheck(entry, duplicateCheckContainer, config, descriptionTextarea) {
    // Move the duplicate check container below the description checkbox container
    const descriptionContainer = document.getElementById('ai-helper-description-checkbox-container');
    if (descriptionContainer && descriptionContainer.parentNode) {
      descriptionContainer.parentNode.insertBefore(duplicateCheckContainer, descriptionContainer.nextSibling);
    }
    duplicateCheckContainer.style.display = 'block';

    const duplicateCheckBtn = document.getElementById('ai-helper-duplicate-check-btn');
    if (duplicateCheckBtn) {
      duplicateCheckBtn.addEventListener('click', function() {
        runDuplicateCheck(entry, config, descriptionTextarea);
      });
    }
  }

  /**
   * Attach the aids of one render, identified by its config container
   * (#ai-helper-issue-textarea-overlay). Each part is created only when its
   * element exists (the description textarea is absent when the user may not
   * edit the description, `safe_attribute?('description')` in Redmine's
   * issues/_form.html.erb). If any step throws, the parts created so far are
   * destroyed and the error rethrown (CRF-098); init() belongs to that guard
   * because it creates DOM and listeners before it can fail. When destroying
   * the parts fails too, both errors are reported in an AggregateError.
   * @param {HTMLElement} overlay The render's config container.
   * @returns {IssueFormAidsEntry} The registry entry for the render, or the existing entry when already attached.
   * @throws {Error} When a data attribute is missing or a part fails to attach.
   */
  function attach(overlay) {
    if (registry.has(overlay)) {
      return registry.get(overlay);
    }

    const config = readConfig(overlay, 'config', 'data-config');
    const descriptionTextarea = document.getElementById('issue_description');
    const entry = { autoCompletion: null, typoChecker: null, duplicateCheckAbort: null, assignmentSuggestion: null, released: false };

    try {
      if (descriptionTextarea && typeof AiHelperAutoCompletion !== 'undefined') {
        const autoCompletion = new AiHelperAutoCompletion(descriptionTextarea, completionOptions(config, {
          contextType: 'description',
          endpoint: config.descriptionEndpoint,
          enabledTooltip: config.labels.enabledTooltip,
          disabledTooltip: config.labels.disabledTooltip
        }));
        // Registered before init(): a failing init() leaves DOM and listeners
        // that the rollback below must destroy
        entry.autoCompletion = autoCompletion;

        autoCompletion.init();
        // init() read the shared localStorage key; put back the state of the
        // completion this render replaces instead (FR-006)
        if (descriptionEnabled !== null) {
          autoCompletion.restoreEnabled(descriptionEnabled);
        }

        // Move the description checkbox to below the description editor
        const descriptionContainer = document.getElementById('ai-helper-description-checkbox-container');
        if (descriptionContainer) {
          AiHelperEditorControls.placeAfterEditor(descriptionTextarea, descriptionContainer);
        }

        // Store reference globally for potential updates
        publishInstance('autoCompletion', autoCompletion);
      }

      if (typeof AiHelperTypoChecker !== 'undefined') {
        entry.typoChecker = AiHelperTypoChecker.initFromConfig(
          document.getElementById('ai-helper-issue-typo-overlay'),
          'issue_description',
          'ai-helper-typo-check-description-btn'
        );
      }

      // Initialize duplicate check for new issues
      const duplicateCheckContainer = document.getElementById('ai-helper-duplicate-check-container');
      if (duplicateCheckContainer && descriptionTextarea) {
        initializeDuplicateCheck(entry, duplicateCheckContainer, config, descriptionTextarea);
      }

      // Wire up the assignee-suggestion feature for the issue's "Assignee" field
      const assignedToSelect = document.getElementById('issue_assigned_to_id');
      if (assignedToSelect && typeof AiHelperAssignmentSuggestion !== 'undefined') {
        const assignConfig = readConfig(overlay, 'assignmentConfig', 'data-assignment-config');
        const suggestion = new AiHelperAssignmentSuggestion({
          endpoint: assignConfig.endpoint,
          robotIconHtml: assignConfig.robotIconHtml,
          labels: assignConfig.labels
        });
        entry.assignmentSuggestion = suggestion;
        suggestion.init();
      }

      registry.set(overlay, entry);
      return entry;
    } catch (error) {
      // Do not leave half-built aids behind: their overlays and listeners
      // would otherwise be stacked again by the next attach
      try {
        releaseEntry(entry);
      } catch (releaseError) {
        throw new AggregateError(
          [error, releaseError],
          `Failed to attach the issue form aids (${error.message}) and to release the parts created so far (${releaseError.message})`,
          { cause: releaseError }
        );
      }
      throw error;
    }
  }

  /**
   * Attach every not-yet-attached config container within `root`. The
   * container is recorded as failed before its attach runs, so a failure
   * surfaces to the caller (and from the observer callback to window.onerror)
   * exactly once and is not retried on every DOM mutation; the next render
   * has a new container and is attached again.
   * @param {Element|Document} root - The element to search (`#all_attributes`, the document, or a config container itself).
   */
  function scan(root) {
    // querySelectorAll skips the root itself (CRF-049), so a container passed
    // directly as root is handled too
    const overlays = Array.from(root.querySelectorAll('#ai-helper-issue-textarea-overlay'));
    if (root instanceof Element && root.matches('#ai-helper-issue-textarea-overlay')) {
      overlays.unshift(root);
    }
    overlays.forEach((overlay) => {
      if (registry.has(overlay) || failedOverlays.has(overlay)) {
        return;
      }
      failedOverlays.add(overlay);
      attach(overlay);
      failedOverlays.delete(overlay);
    });
  }

  /**
   * Release the aids of registered renders that have left the document
   * (replaceIssueFormWith emptied #all_attributes). The global completion
   * reference is cleared before the next attach can overwrite it (R-005). The
   * description completion's on/off state is recorded first for the next
   * render (FR-006). An entry leaves the registry before it is released, so a
   * release that throws surfaces once instead of on every later mutation.
   */
  function releaseDetached() {
    // isConnected also catches the removal of an ancestor of the container
    registry.forEach((entry, overlay) => {
      if (!overlay.isConnected) {
        registry.delete(overlay);
        if (entry.autoCompletion) {
          descriptionEnabled = entry.autoCompletion.isEnabled;
        }
        releaseEntry(entry);
      }
    });
  }

  /**
   * Create the notes-field aids (completion and typo check) for a persisted
   * issue's edit form. They live in fieldset#add_notes, outside
   * #all_attributes, so re-rendering the form never replaces them: they are
   * attached once at page display and are not part of the per-render
   * registry (R-004). The settings come from the page-level config container.
   * @throws {Error} When the persisted issue's notes editor has no notes
   *   controls (they are rendered by ai_helper/issues/_notes_controls).
   */
  function attachNotes() {
    if (notesAttached) {
      return;
    }
    const overlay = document.getElementById('ai-helper-issue-textarea-overlay');
    if (!overlay) {
      return;
    }
    const config = readConfig(overlay, 'config', 'data-config');
    const notesTextarea = document.getElementById('issue_notes');
    if (!notesTextarea || typeof AiHelperAutoCompletion === 'undefined' || !config.isPersistedIssue) {
      return;
    }
    const notesContainer = document.getElementById('ai-helper-notes-checkbox-container');
    if (!notesContainer) {
      throw new Error('#ai-helper-notes-checkbox-container is missing although the edit form has a notes editor');
    }
    notesAttached = true;

    const notesAutoCompletion = new AiHelperAutoCompletion(notesTextarea, completionOptions(config, {
      contextType: 'note',
      endpoint: config.notesEndpoint,
      enabledTooltip: config.labels.noteEnabledTooltip,
      disabledTooltip: config.labels.noteDisabledTooltip,
      issueId: config.issueId,
      projectId: config.projectId
    }));

    notesAutoCompletion.init();

    // Move the notes checkbox to right below the notes editor
    AiHelperEditorControls.placeAfterEditor(notesTextarea, notesContainer);

    // Store reference globally for potential updates
    publishInstance('notesAutoCompletion', notesAutoCompletion);

    if (typeof AiHelperTypoChecker !== 'undefined') {
      AiHelperTypoChecker.initFromConfig(
        document.getElementById('ai-helper-issue-typo-overlay'),
        'issue_notes',
        'ai-helper-typo-check-notes-btn'
      );
    }
  }

  /**
   * Observe #all_attributes so every re-render is picked up and every render
   * that left the document is released. Pages without #all_attributes get no
   * observer. A second call disconnects the previous observer. An error of
   * the callback surfaces as an uncaught error; the scan still runs when the
   * release threw, so the new render is attached either way.
   */
  function observeAllAttributes() {
    const allAttributes = document.getElementById('all_attributes');
    if (!allAttributes) {
      return;
    }

    if (observer) {
      observer.disconnect();
    }
    observer = new MutationObserver(() => {
      try {
        // Release first so window.aiHelperInstances.autoCompletion is cleared
        // before the new render's attach overwrites it (R-002, R-005)
        releaseDetached();
      } finally {
        scan(allAttributes);
      }
    });
    observer.observe(allAttributes, { childList: true });
  }

  /**
   * Scan the existing config containers in the document, attach the notes
   * aids and observe #all_attributes. A failing step does not keep the later
   * ones from running: the notes aids and the observer are set up regardless,
   * then the error is rethrown.
   */
  function start() {
    try {
      try {
        scan(document);
      } finally {
        attachNotes();
      }
    } finally {
      observeAllAttributes();
    }
  }

  /**
   * Look up the entry of a render. Meant for tests and diagnostics: the entry
   * is the live object, callers must not modify it.
   * @param {HTMLElement} overlay - The config container of a render.
   * @returns {IssueFormAidsEntry|undefined} The registry entry for the render, if attached.
   */
  function entryFor(overlay) {
    return registry.get(overlay);
  }

  return { attach, scan, releaseDetached, start, entryFor };
})();

window.AiHelperIssueFormAids = AiHelperIssueFormAids;

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => {
    window.AiHelperIssueFormAids.start();
  });
} else {
  window.AiHelperIssueFormAids.start();
}
