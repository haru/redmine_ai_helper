/**
 * Issue auto-completion, duplicate check, and typo checker initialization.
 * Extracted from shared/_textarea_overlay.html.erb.
 */

function removeExistingNotesCheckbox() {
  const existingNotesCheckbox = document.getElementById('ai-helper-notes-checkbox-container');
  if (existingNotesCheckbox) {
    existingNotesCheckbox.remove();
  }
}
removeExistingNotesCheckbox();

/**
 * Move `container` to immediately follow `textarea` in the DOM and reveal it.
 * @param {HTMLElement} textarea
 * @param {HTMLElement} container
 */
function moveContainerAfterTextarea(textarea, container) {
  const parent = textarea.parentNode;
  const nextSibling = textarea.nextSibling;
  if (nextSibling) {
    parent.insertBefore(container, nextSibling);
  } else {
    parent.appendChild(container);
  }
  container.style.display = 'block';
}

/**
 * Wire up description/notes auto-completion, duplicate-check, and
 * checkbox placement for the issue textarea overlay.
 */
function initializeIssueCompletion() {

  // Prevent multiple initialization by checking if already processed
  if (window.aiHelperAutoCompletionInitialized) {
    return;
  }


  // Find ticket description and notes textarea elements
  const descriptionTextarea = document.getElementById('issue_description');
  const notesTextarea = document.getElementById('issue_notes');

  const container = document.getElementById('ai-helper-issue-textarea-overlay');
  if (!container) return;
  const config = JSON.parse(container.dataset.config || '{}');

  // Initialize autocompletion for description field
  if (descriptionTextarea && typeof AiHelperAutoCompletion !== 'undefined') {

    const autoCompletion = new AiHelperAutoCompletion(descriptionTextarea, {
      contextType: 'description',
      endpoint: config.descriptionEndpoint,
      userId: config.userId,
      debounceDelay: config.debounceDelay,
      minLength: config.minLength,
      suggestionColor: config.suggestionColor,
      // I18n labels
      labels: {
        commonToggleLabel: config.labels.commonToggleLabel,
        loading: config.labels.loading,
        noSuggestions: config.labels.noSuggestions,
        acceptSuggestion: config.labels.acceptSuggestion,
        dismiss: config.labels.dismiss,
        enabledTooltip: config.labels.enabledTooltip,
        disabledTooltip: config.labels.disabledTooltip
      }
    });

    autoCompletion.init();

    // Move the description checkbox to below the description textarea

    const descriptionContainer = document.getElementById('ai-helper-description-checkbox-container');

    if (descriptionContainer && descriptionTextarea) {
      moveContainerAfterTextarea(descriptionTextarea, descriptionContainer);
    }


    // Store reference globally for potential updates
    if (!window.aiHelperInstances) {
      window.aiHelperInstances = {};
    }
    window.aiHelperInstances.autoCompletion = autoCompletion;
  }

  // Initialize duplicate check for new issues
  const duplicateCheckContainer = document.getElementById('ai-helper-duplicate-check-container');
  if (duplicateCheckContainer && descriptionTextarea) {
    // Move the duplicate check container below the description checkbox container
    const descriptionContainer = document.getElementById('ai-helper-description-checkbox-container');
    if (descriptionContainer && descriptionContainer.parentNode) {
      descriptionContainer.parentNode.insertBefore(duplicateCheckContainer, descriptionContainer.nextSibling);
    }
    duplicateCheckContainer.style.display = 'block';

    // Initialize duplicate check functionality
    const duplicateCheckBtn = document.getElementById('ai-helper-duplicate-check-btn');
    const duplicateCheckResults = document.getElementById('ai-helper-duplicate-check-results');
    const duplicateCheckLoading = document.getElementById('ai-helper-duplicate-check-loading');
    const subjectInput = document.getElementById('issue_subject');

    if (duplicateCheckBtn) {
      duplicateCheckBtn.addEventListener('click', async function() {
        const subject = subjectInput ? subjectInput.value : '';
        const description = descriptionTextarea ? descriptionTextarea.value : '';

        if (!subject.trim() && !description.trim()) {
          alert(config.duplicateCheckLabels.emptyContent);
          return;
        }

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
            body: JSON.stringify({
              subject: subject,
              description: description
            })
          });

          if (!response.ok) {
            const errorData = await response.json();
            throw new Error(errorData.error || 'Unknown error');
          }

          const html = await response.text();
          duplicateCheckResults.innerHTML = html;
          duplicateCheckResults.style.display = 'block';
        } catch (error) {
          console.error('Duplicate check error:', error);
          duplicateCheckResults.innerHTML = '';
          const errorParagraph = document.createElement('p');
          errorParagraph.className = 'ai-helper-error';
          errorParagraph.textContent = error.message;
          duplicateCheckResults.appendChild(errorParagraph);
          duplicateCheckResults.style.display = 'block';
        } finally {
          duplicateCheckLoading.style.display = 'none';
          duplicateCheckBtn.classList.remove('disabled');
        }
      });
    }
  }

  // Initialize autocompletion for notes field (only for existing issues, not for new issue creation)
  if (notesTextarea && typeof AiHelperAutoCompletion !== 'undefined' && config.isPersistedIssue) {

    const notesAutoCompletion = new AiHelperAutoCompletion(notesTextarea, {
      contextType: 'note',
      endpoint: config.notesEndpoint,
      userId: config.userId,
      debounceDelay: config.debounceDelay,
      minLength: config.minLength,
      suggestionColor: config.suggestionColor,
      issueId: config.issueId,
      projectId: config.projectId,
      // I18n labels
      labels: {
        commonToggleLabel: config.labels.commonToggleLabel,
        loading: config.labels.loading,
        noSuggestions: config.labels.noSuggestions,
        acceptSuggestion: config.labels.acceptSuggestion,
        dismiss: config.labels.dismiss,
        enabledTooltip: config.labels.noteEnabledTooltip,
        disabledTooltip: config.labels.noteDisabledTooltip
      }
    });

    notesAutoCompletion.init();

    // Move the notes checkbox to right below the notes textarea

    const notesContainer = document.getElementById('ai-helper-notes-checkbox-container');

    if (notesContainer && notesTextarea) {
      moveContainerAfterTextarea(notesTextarea, notesContainer);
    }


    // Store reference globally for potential updates
    if (!window.aiHelperInstances) {
      window.aiHelperInstances = {};
    }
    window.aiHelperInstances.notesAutoCompletion = notesAutoCompletion;
  }

}

/**
 * Bind the typo-check button/overlay for the issue description and notes textareas.
 */
function initializeIssueTypoChecker() {
  const container = document.getElementById('ai-helper-issue-typo-overlay');
  if (!container) return;

  window.AiHelperTypoChecker.initFromConfig(
    container, 'issue_description', 'ai-helper-typo-check-description-btn'
  );
  window.AiHelperTypoChecker.initFromConfig(
    container, 'issue_notes', 'ai-helper-typo-check-notes-btn'
  );
}

/**
 * Wire up the assignee-suggestion feature for the issue's "Assignee" field.
 */
function initializeAssignmentSuggestion() {
  const container = document.getElementById('ai-helper-issue-textarea-overlay');
  if (!container) return;
  const assignConfig = JSON.parse(container.dataset.assignmentConfig || '{}');

  if (typeof AiHelperAssignmentSuggestion === 'undefined') return;
  const assignedToSelect = document.getElementById('issue_assigned_to_id');
  if (!assignedToSelect) return;

  const suggestion = new AiHelperAssignmentSuggestion({
    endpoint: assignConfig.endpoint,
    robotIconHtml: assignConfig.robotIconHtml,
    labels: assignConfig.labels
  });
  suggestion.init();
}

setTimeout( function() {
  initializeIssueCompletion();
  initializeIssueTypoChecker();
  initializeAssignmentSuggestion();
}, 500); // Delay to ensure DOM is fully loaded
