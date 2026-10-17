// Swapping the server-rendered report into the result area after a
// generation finishes, and rebuilding the export links for the saved
// report. Split out of ai_helper_project_health.js to keep that file under
// the max-lines ESLint limit (see ADR-027). Relies on hiddenFieldContainerOf
// declared there (exposed as a global), so must load after
// ai_helper_project_health.js.

/**
 * Fetch the server-rendered content of the saved report and swap it into
 * the result area, replacing the client-rendered body: the saved report's
 * charts only exist in the server-rendered markup. Export links are rebuilt
 * from the response's data attributes so they lead to the saved report's
 * own PDF / Markdown endpoints.
 * @param {HTMLElement} resultDiv - The report result container.
 * @param {number} savedReportId - The saved report's id, taken from the
 *   health_report_saved SSE event.
 * @returns {Promise<void>} Resolves when the swap is done, rejects when the
 *   request fails. Resolves without swapping when the result area was
 *   detached from the document while the request was in flight.
 * @throws {Error} When the content-url meta tag is missing.
 */
function swapInSavedReportContent(resultDiv, savedReportId) {
  const meta = document.querySelector('meta[name="ai-helper-health-report-content-url"]');
  if (!meta) {
    throw new Error(
      'the ai-helper-health-report-content-url meta tag is missing; the saved report content cannot be loaded',
    );
  }
  const url = meta.getAttribute('content').replace('__REPORT_ID__', String(savedReportId));
  return fetch(url, { credentials: 'same-origin' })
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
 * Build the export links for the swapped-in saved report from its data
 * attributes. The links deliberately carry no ids: the POST-based export
 * click handler selects its links by their `-dynamic` ids, and these links
 * navigate to the saved report's exports instead.
 * @param {HTMLElement} resultDiv - The report result container holding the
 *   swapped-in `.ai-helper-health-report-content` root element.
 */
function addReportExportLinks(resultDiv) {
  const contentRoot = resultDiv.querySelector('.ai-helper-health-report-content');
  if (!contentRoot) {
    return;
  }
  const markdownUrl = contentRoot.getAttribute('data-markdown-url');
  const pdfUrl = contentRoot.getAttribute('data-pdf-url');
  if (!markdownUrl && !pdfUrl) {
    return;
  }

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

  const markdownSpan = document.createElement('span');
  const markdownLink = document.createElement('a');
  markdownLink.href = markdownUrl || '#';
  markdownLink.className = 'text';
  markdownLink.textContent = 'Markdown';
  markdownSpan.appendChild(markdownLink);
  otherFormatsP.appendChild(markdownSpan);

  otherFormatsP.appendChild(document.createTextNode(' '));

  const pdfSpan = document.createElement('span');
  const pdfLink = document.createElement('a');
  pdfLink.href = pdfUrl || '#';
  pdfLink.className = 'pdf';
  pdfLink.textContent = 'PDF';
  pdfSpan.appendChild(pdfLink);
  otherFormatsP.appendChild(pdfSpan);

  contentContainer.appendChild(otherFormatsP);
}

// Make the entry point visible to ai_helper_project_health.js, which runs
// inside its own load guard.
window.swapInSavedReportContent = swapInSavedReportContent;
