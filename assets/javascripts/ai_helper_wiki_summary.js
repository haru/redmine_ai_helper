/**
 * Wiki summary display: XHR fetch of the cached/generated summary, and the
 * collapsible fieldset that hosts it.
 * Extracted from wiki/_summary.html.erb.
 */

/**
 * Fetch the (cached or freshly generated) wiki summary and render it into
 * the summary area. Exposed on `window` because ai_helper.js calls it
 * directly after a summary-generation stream completes.
 *
 * @param {boolean} [update] - when true, requests a forced regeneration.
 */
function getWikiSummary(update) {
  const container = document.getElementById('ai-helper-wiki-summary-fields');
  if (!container) return;
  const config = JSON.parse(container.dataset.config || '{}');

  let url = config.summaryUrl;
  if (update === true) {
    url += '?update=true';
  }

  const summaryArea = document.getElementById('ai-helper-wiki-summary-area');
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
window.getWikiSummary = getWikiSummary;

function generateWikiSummaryStream() {
  const container = document.getElementById('ai-helper-wiki-summary-fields');
  if (!container) return;
  const config = JSON.parse(container.dataset.config || '{}');
  ai_helper.generateWikiSummaryStream(config.generateUrl, config.errorMessage);
}

/**
 * Toggle the open/closed state of the wiki summary fieldset.
 * @param {boolean} flag - true to expand, false to collapse.
 */
function aiHelperSetWikiSummayExpanded(flag) {
  AiHelperCollapsibleFieldset.setExpanded('ai-helper-wiki-summary-fields', flag);
}

/**
 * Save the open/closed state of the fieldset to localStorage. Exposed on
 * `window` because the fieldset legend's inline `onclick` calls it directly.
 */
function aiHelperSaveWikiSummaryState() {
  const fieldset = document.getElementById('ai-helper-wiki-summary-fields');
  const isOpen = !fieldset.classList.contains('collapsed');
  const config = JSON.parse(fieldset.dataset.config || '{}');
  localStorage.setItem('aiHelperWikiSummaryState_' + config.userId, isOpen ? 'expanded' : 'collapsed');
}
window.aiHelperSaveWikiSummaryState = aiHelperSaveWikiSummaryState;

function initWikiSummary() {
  const container = document.getElementById('ai-helper-wiki-summary-fields');
  if (!container) return;
  const config = JSON.parse(container.dataset.config || '{}');

  const summaryButtons = document.querySelectorAll('.ai-helper-wiki-summary-button');
  summaryButtons.forEach(function(button) {
    button.addEventListener('click', function(e) {
      e.preventDefault();
      generateWikiSummaryStream();
    });
  });

  // Move wiki summary to top of wiki content and set up state
  const wikiContent = document.querySelector('#content .wiki');
  if (wikiContent) {
    wikiContent.parentNode.insertBefore(container, wikiContent);
    container.style.display = 'block';
  }

  const savedState = localStorage.getItem('aiHelperWikiSummaryState_' + config.userId);
  if (savedState === 'expanded') {
    aiHelperSetWikiSummayExpanded(true);
  } else {
    aiHelperSetWikiSummayExpanded(false);
  }

  if (config.hasSummary) {
    getWikiSummary();
  }
}

document.addEventListener('DOMContentLoaded', initWikiSummary);
