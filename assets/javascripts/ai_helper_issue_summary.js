/**
 * Issue summary panel: XHR fetch of the cached/generated summary, the
 * collapsible fieldset that hosts it, and the similar-issues panel with its
 * suggested-hours effort estimation UI.
 * Extracted from issues/_bottom.html.erb.
 */

function getIssueSummaryConfig() {
  const container = document.getElementById('ai-helper-summary-fields');
  return container ? JSON.parse(container.dataset.config || '{}') : {};
}

/**
 * Fetch the (cached or freshly generated) issue summary and render it into
 * the summary area. Exposed on `window` because ai_helper.js calls it
 * directly after a summary-generation stream completes.
 *
 * @param {boolean} [update] - when true, requests a forced regeneration.
 */
function getSummary(update) {
  const config = getIssueSummaryConfig();
  let url = config.summaryUrl;
  if (update === true) {
    url += '?update=true';
  }

  const summaryArea = document.getElementById('ai-helper-summary-area');
  if (summaryArea) {
    summaryArea.innerHTML = '<div class="ai-helper-loader"></div>';
  }

  const xhr = new XMLHttpRequest();
  xhr.open('GET', url, true);
  xhr.onload = function() {
    if (xhr.status === 200) {
      if (summaryArea) {
        summaryArea.innerHTML = xhr.responseText;
      }
    } else {
      if (summaryArea) {
        summaryArea.innerHTML = '<div class="error">' + config.errorMessage + ': ' + xhr.statusText + '</div>';
      }
    }
  };
  xhr.onerror = function() {
    if (summaryArea) {
      summaryArea.innerHTML = '<div class="error">' + config.errorMessage + '</div>';
    }
  };
  xhr.send();
}
window.getSummary = getSummary;

function generateSummaryStream() {
  const config = getIssueSummaryConfig();
  ai_helper.generateSummaryStream(config.generateUrl, config.errorMessage);
}
window.generateSummaryStream = generateSummaryStream;

/**
 * Toggle the open/closed state of the issue summary fieldset.
 * @param {boolean} flag - true to expand, false to collapse.
 */
function aiHelperSetSummaryExpanded(flag) {
  AiHelperCollapsibleFieldset.setExpanded('ai-helper-summary-fields', flag);
}

/**
 * Save the open/closed state of the fieldset to localStorage. Exposed on
 * `window` because the fieldset legend's inline `onclick` calls it directly.
 */
function aiHelperSaveSummaryState() {
  const fieldset = document.getElementById('ai-helper-summary-fields');
  const isOpen = !fieldset.classList.contains('collapsed');
  const config = getIssueSummaryConfig();
  localStorage.setItem('aiHelperIssueSummaryState_' + config.userId, isOpen ? 'expanded' : 'collapsed');
}
window.aiHelperSaveSummaryState = aiHelperSaveSummaryState;

/**
 * Fetch similar issues for the currently-selected scope. Exposed on
 * `window` because the "similar issues" link's inline `onclick` calls it
 * directly.
 */
function findSimilarIssues() {
  const config = getIssueSummaryConfig();
  const scope = getSelectedScope();
  const url = config.similarIssuesUrl + '?scope=' + encodeURIComponent(scope);
  const similarIssuesArea = document.getElementById('ai-helper-similar-issues-area');

  if (similarIssuesArea) {
    similarIssuesArea.innerHTML = '<div class="ai-helper-loader"></div>';
  }

  const xhr = new XMLHttpRequest();
  xhr.open('GET', url, true);
  xhr.onload = function() {
    if (xhr.status === 200) {
      if (similarIssuesArea) {
        similarIssuesArea.innerHTML = xhr.responseText;
        refreshEffortUI();
      }
    } else {
      if (similarIssuesArea) {
        similarIssuesArea.innerHTML = '<div class="error">' + config.errorMessage + ': ' + xhr.statusText + '</div>';
      }
    }
  };
  xhr.onerror = function() {
    if (similarIssuesArea) {
      similarIssuesArea.innerHTML = '<div class="error">' + config.errorMessage + '</div>';
    }
  };
  xhr.send();
}
window.findSimilarIssues = findSimilarIssues;

// Get selected scope value from radio buttons
function getSelectedScope() {
  const selected = document.querySelector('input[name="ai_helper_scope"]:checked');
  return selected ? selected.value : 'with_subprojects';
}

// Recompute the suggested hours weighted average from the currently
// checked similar issues, mirroring RedmineAiHelper::EffortEstimation.suggest.
function recalculateSuggestedHours() {
  const block = document.getElementById('ai-helper-suggested-hours-block');
  if (!block) return;

  const checkboxes = document.querySelectorAll('.ai-helper-effort-checkbox:checked');
  let weightedSum = 0;
  let totalWeight = 0;
  let includedCount = 0;
  checkboxes.forEach(function(checkbox) {
    const spentHours = parseFloat(checkbox.dataset.spentHours);
    const score = parseFloat(checkbox.dataset.similarityScore);
    // Checkboxes for similar issues without spent_hours data carry no
    // data-spent-hours attribute (parseFloat(undefined) is NaN); skip them
    // so they can't poison the weighted average with NaN.
    if (!Number.isFinite(spentHours) || !Number.isFinite(score)) return;
    weightedSum += spentHours * score;
    totalWeight += score;
    includedCount += 1;
  });

  if (totalWeight === 0) {
    block.style.display = 'none';
    return;
  }

  block.style.display = '';
  const suggestedHours = Math.round((weightedSum / totalWeight) * 10) / 10;

  const valueSpan = document.getElementById('ai-helper-suggested-hours-value');
  if (valueSpan) {
    valueSpan.textContent = suggestedHours.toFixed(1);
  }

  const noteSpan = document.getElementById('ai-helper-suggested-hours-note');
  if (noteSpan) {
    noteSpan.textContent = '(' + block.dataset.noteTemplate.replace('%{count}', includedCount) + ')';
  }
}

// Recompute both the suggested hours and the select-all checkbox state.
// These two are always refreshed together whenever the checked set of
// effort checkboxes may have changed.
function refreshEffortUI() {
  recalculateSuggestedHours();
  recalculateEffortSelectAllState();
}

// Set every row effort checkbox to match the header select-all checkbox,
// then recompute the suggestion.
function toggleAllEffortCheckboxes(checked) {
  const checkboxes = document.querySelectorAll('.ai-helper-effort-checkbox');
  checkboxes.forEach(function(checkbox) {
    checkbox.checked = checked;
  });
  refreshEffortUI();
}

// Recompute the header select-all checkbox's checked/indeterminate state
// from the current row checkboxes: all checked -> checked, none checked ->
// unchecked, a mix of both -> indeterminate.
function recalculateEffortSelectAllState() {
  const selectAll = document.getElementById('ai-helper-effort-select-all');
  if (!selectAll) return;

  const checkboxes = document.querySelectorAll('.ai-helper-effort-checkbox');
  const checkedCount = Array.from(checkboxes).filter(function(checkbox) { return checkbox.checked; }).length;

  if (checkboxes.length === 0 || checkedCount === 0) {
    selectAll.checked = false;
    selectAll.indeterminate = false;
  } else if (checkedCount === checkboxes.length) {
    selectAll.checked = true;
    selectAll.indeterminate = false;
  } else {
    selectAll.checked = false;
    selectAll.indeterminate = true;
  }
}

// Write the currently suggested hours into the issue's Estimated time field.
// That field lives inside the "#update" edit form, which Redmine keeps
// collapsed (display:none) until the user opens it, so reveal and scroll to
// it (via Redmine core's own showAndScrollTo helper) to make the change visible.
function applySuggestedHours() {
  const valueSpan = document.getElementById('ai-helper-suggested-hours-value');
  const estimatedHoursField = document.getElementById('issue_estimated_hours');
  if (valueSpan && estimatedHoursField) {
    estimatedHoursField.value = valueSpan.textContent;
    showAndScrollTo('update', 'issue_estimated_hours');
  }
}

// Function to move similar issues section to after relations
function moveSimilarIssuesToRelations() {
  const similarIssuesSection = document.getElementById('ai-helper-similar-issues-section');
  if (!similarIssuesSection) return;

  // Look for relations section
  const relationsDiv = document.getElementById('relations');
  if (relationsDiv) {
    // Insert after relations div
    relationsDiv.parentNode.insertBefore(similarIssuesSection, relationsDiv.nextSibling);
  }
}

document.addEventListener('DOMContentLoaded', function() {
  const container = document.getElementById('ai-helper-summary-fields');
  if (!container) return;
  const config = getIssueSummaryConfig();

  const summaryButtons = document.querySelectorAll('.ai-helper-summary-button');
  summaryButtons.forEach(function(button) {
    button.addEventListener('click', function(e) {
      e.preventDefault();
      generateSummaryStream();
    });
  });

  const savedState = localStorage.getItem('aiHelperIssueSummaryState_' + config.userId);
  if (savedState === 'expanded') {
    aiHelperSetSummaryExpanded(true);
  } else {
    aiHelperSetSummaryExpanded(false);
  }

  if (config.hasSummary) {
    getSummary();
  }

  // Move similar issues to relations area
  moveSimilarIssuesToRelations();

  // Handle effort checkbox toggling, the select-all header checkbox, and
  // the Apply button inside the dynamically-loaded similar issues area
  // (event delegation, since its content is replaced via innerHTML after
  // the initial page load).
  const similarIssuesArea = document.getElementById('ai-helper-similar-issues-area');
  if (similarIssuesArea) {
    similarIssuesArea.addEventListener('change', function(e) {
      if (e.target.classList.contains('ai-helper-effort-checkbox')) {
        refreshEffortUI();
      } else if (e.target.id === 'ai-helper-effort-select-all') {
        toggleAllEffortCheckboxes(e.target.checked);
      }
    });
    similarIssuesArea.addEventListener('click', function(e) {
      const applyButton = e.target.closest('#ai-helper-apply-suggested-hours');
      if (applyButton) {
        e.preventDefault();
        applySuggestedHours();
      }
    });
    refreshEffortUI();
  }
});
