// Swapping the server-rendered report into the result area after a
// generation finishes, and rebuilding the export links for the saved
// report. Split out of ai_helper_project_health.js to keep that file under
// the max-lines ESLint limit (see ADR-027). Relies on hiddenFieldContainerOf
// declared there (exposed as a global), so must load after
// ai_helper_project_health.js.

/**
 * Build the URL of the saved report's server-rendered content. Called before
 * the result area is touched so a bad id or a missing meta tag fails while
 * the page is still as it was.
 * @param {number} savedReportId - The saved report's id, taken from the
 *   health_report_saved SSE event.
 * @returns {string} The content URL.
 * @throws {Error} When the id is not a positive integer or the content-url
 *   meta tag is missing.
 */
function savedReportContentUrl(savedReportId) {
  if (!Number.isInteger(savedReportId) || savedReportId <= 0) {
    throw new Error('the saved report id must be a positive integer, got ' + JSON.stringify(savedReportId));
  }
  const meta = document.querySelector('meta[name="ai-helper-health-report-content-url"]');
  if (!meta) {
    throw new Error(
      'the ai-helper-health-report-content-url meta tag is missing; the saved report content cannot be loaded',
    );
  }
  return meta.getAttribute('content').replace('__REPORT_ID__', String(savedReportId));
}

/**
 * Fetch the server-rendered content of the saved report and swap it into
 * the result area, replacing the client-rendered body: the saved report's
 * charts only exist in the server-rendered markup. Export links are rebuilt
 * from the response's data attributes so they lead to the saved report's
 * own PDF / Markdown endpoints.
 * @param {HTMLElement} resultDiv - The report result container.
 * @param {string} contentUrl - The URL from savedReportContentUrl().
 * @returns {Promise<void>} Resolves when the swap is done, rejects when the
 *   request fails or the response lacks the content root or its export
 *   URLs. Resolves without swapping when the result area was detached from
 *   the document while the request was in flight.
 */
function swapInSavedReportContent(resultDiv, contentUrl) {
  return fetch(contentUrl, { credentials: 'same-origin' })
    .then(function(response) {
      if (!response.ok) {
        throw new Error('Failed to load the saved report content (HTTP ' + response.status + ')');
      }
      return response.text();
    })
    .then(function(html) {
      // Selecting another report while the request was in flight replaces
      // the whole detail pane, detaching the result area together with its
      // content container; the newly shown pane must not receive this
      // report's body.
      if (!resultDiv.isConnected) {
        return;
      }
      resultDiv.innerHTML = html;
      addReportExportLinks(resultDiv);
    });
}

/**
 * Read a required export URL from the content root.
 * @param {Element} contentRoot - The `.ai-helper-health-report-content` element.
 * @param {string} attribute - The data attribute holding the URL.
 * @returns {string} The URL.
 * @throws {Error} When the attribute is missing or empty.
 */
function requiredExportUrl(contentRoot, attribute) {
  const url = contentRoot.getAttribute(attribute);
  if (!url) {
    throw new Error('the saved report content has no ' + attribute);
  }
  return url;
}

/**
 * Build one export link wrapped in a span.
 * @param {string} href - The link target.
 * @param {string} className - The Redmine export class (`text` or `pdf`).
 * @param {string} label - The link text.
 * @returns {HTMLSpanElement} The span holding the link.
 */
function exportLinkSpan(href, className, label) {
  const span = document.createElement('span');
  const link = document.createElement('a');
  link.href = href;
  link.className = className;
  link.textContent = label;
  span.appendChild(link);
  return span;
}

/**
 * Build the export links for the swapped-in saved report from its data
 * attributes. The links deliberately carry no ids: the POST-based export
 * click handler selects its links by their `-dynamic` ids, and these links
 * navigate to the saved report's exports instead. POST-based links that the
 * project overview's observer added during generation are removed first, so
 * only the saved report's links remain.
 * @param {HTMLElement} resultDiv - The report result container holding the
 *   swapped-in `.ai-helper-health-report-content` root element.
 * @throws {Error} When the content root or one of its export URLs is missing.
 */
function addReportExportLinks(resultDiv) {
  const contentRoot = resultDiv.querySelector('.ai-helper-health-report-content');
  if (!contentRoot) {
    throw new Error('the saved report content has no .ai-helper-health-report-content root');
  }
  const markdownUrl = requiredExportUrl(contentRoot, 'data-markdown-url');
  const pdfUrl = requiredExportUrl(contentRoot, 'data-pdf-url');

  document.querySelectorAll('#ai-helper-pdf-export-link-dynamic, #ai-helper-markdown-export-link-dynamic')
    .forEach(function(link) {
      const row = link.closest('.other-formats');
      if (row) {
        row.remove();
      }
    });

  const contentContainer = hiddenFieldContainerOf(resultDiv);
  if (contentContainer.querySelector('.other-formats')) {
    return;
  }

  const otherFormatsP = document.createElement('p');
  otherFormatsP.className = 'other-formats';
  const exportLabel = document.querySelector('meta[name="export-label"]');
  otherFormatsP.appendChild(
    document.createTextNode((exportLabel ? exportLabel.getAttribute('content') : 'Export to') + ' '),
  );
  otherFormatsP.appendChild(exportLinkSpan(markdownUrl, 'text', 'Markdown'));
  otherFormatsP.appendChild(document.createTextNode(' '));
  otherFormatsP.appendChild(exportLinkSpan(pdfUrl, 'pdf', 'PDF'));
  contentContainer.appendChild(otherFormatsP);
}

/**
 * Show the generic error message in the result area after swapping in the
 * saved report failed, and log the cause. The client-rendered body would
 * otherwise look finished while lacking its charts and export links.
 * @param {HTMLElement} resultDiv - The report result container.
 * @param {Error} error - The failure.
 */
function showSavedReportSwapError(resultDiv, error) {
  console.error('Failed to swap in the saved health report:', error);
  const errorMessage = document.querySelector('meta[name="error-message"]');
  const box = document.createElement('div');
  box.className = 'ai-helper-error';
  box.textContent = errorMessage ? errorMessage.getAttribute('content') : 'Error';
  resultDiv.replaceChildren(box);
}

// Make the entry point visible to ai_helper_project_health.js, which runs
// inside its own load guard.
window.savedReportContentUrl = savedReportContentUrl;
window.swapInSavedReportContent = swapInSavedReportContent;
window.showSavedReportSwapError = showSavedReportSwapError;
