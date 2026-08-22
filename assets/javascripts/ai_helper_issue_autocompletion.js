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

function initalizeIssueCompletion() {

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
      const parent = descriptionTextarea.parentNode;
      const nextSibling = descriptionTextarea.nextSibling;
      if (nextSibling) {
        parent.insertBefore(descriptionContainer, nextSibling);
      } else {
        parent.appendChild(descriptionContainer);
      }
      descriptionContainer.style.display = 'block';
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
      const parent = notesTextarea.parentNode;
      const nextSibling = notesTextarea.nextSibling;

      if (nextSibling) {
        parent.insertBefore(notesContainer, nextSibling);
      } else {
        parent.appendChild(notesContainer);
      }
      notesContainer.style.display = 'block';
    }


    // Store reference globally for potential updates
    if (!window.aiHelperInstances) {
      window.aiHelperInstances = {};
    }
    window.aiHelperInstances.notesAutoCompletion = notesAutoCompletion;
  }

}

// Initialize typo checking with direct button binding
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

// Initialize assignment suggestion
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
  initalizeIssueCompletion();
  initializeIssueTypoChecker();
  initializeAssignmentSuggestion();
}, 500); // Delay to ensure DOM is fully loaded
