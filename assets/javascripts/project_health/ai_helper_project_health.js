// Guard against multiple script loading
if (!window.aiHelperProjectHealthInitialized) {
  window.aiHelperProjectHealthInitialized = true;

  /**
   * Read the project health metadata endpoint URL and "created" label from
   * their meta tags.
   * @returns {{url: string|null, label: string}} The metadata refresh config.
   */
  function getProjectHealthMetadataConfig() {
    const urlMeta = document.querySelector('meta[name="ai-helper-project-health-metadata-url"]');
    const labelMeta = document.querySelector('meta[name="ai-helper-project-health-created-label"]');
    return {
      url: urlMeta ? urlMeta.getAttribute('content') : null,
      label: labelMeta ? labelMeta.getAttribute('content') : ''
    };
  }

  /**
   * Render (or remove, if `formattedValue` is falsy) the "created" metadata
   * paragraph above the health report.
   * @param {string} label - The metadata label (e.g. "Created").
   * @param {string|null} formattedValue - The formatted timestamp, or null/empty to clear it.
   */
  function renderProjectHealthMetadata(label, formattedValue) {
    const container = document.querySelector('.ai-helper-project-health');
    if (!container) {
      return;
    }

    let metaParagraph = document.getElementById('ai-helper-project-health-meta');

    if (!formattedValue) {
      if (metaParagraph) {
        metaParagraph.remove();
      }
      return;
    }

    if (!metaParagraph) {
      metaParagraph = document.createElement('p');
      metaParagraph.id = 'ai-helper-project-health-meta';
      metaParagraph.className = 'ai-helper-project-health-meta';
      const contextual = container.querySelector('.contextual');
      if (contextual) {
        contextual.insertAdjacentElement('afterend', metaParagraph);
      } else {
        container.insertBefore(metaParagraph, container.firstChild);
      }
    }

    while (metaParagraph.firstChild) {
      metaParagraph.removeChild(metaParagraph.firstChild);
    }
    const strong = document.createElement('strong');
    strong.textContent = label + ':';
    metaParagraph.appendChild(strong);
    metaParagraph.appendChild(document.createTextNode(' ' + formattedValue));
  }

  /**
   * Fetch the latest "created" metadata for the report and re-render it.
   * Silently ignores failures so a metadata refresh never interrupts the UX.
   */
  function refreshProjectHealthMetadata() {
    const metadata = getProjectHealthMetadataConfig();
    if (!metadata.url) {
      return;
    }

    fetch(metadata.url, {
      headers: { 'Accept': 'application/json' },
      credentials: 'same-origin'
    })
      .then(function(response) {
        if (response.status === 204) {
          renderProjectHealthMetadata(metadata.label, null);
          return null;
        }
        if (!response.ok) {
          throw new Error('Failed to load metadata');
        }
        return response.json();
      })
      .then(function(data) {
        if (!data) {
          return;
        }
        renderProjectHealthMetadata(metadata.label, data.created_on_formatted);
      })
      .catch(function() {
        // Ignore metadata refresh errors to avoid interrupting UX
      });
  }

  /**
   * Auto-scroll the streaming result container to the bottom. Split out to
   * keep the eventSource.onmessage handler under ESLint's max-depth limit.
   */
  function scrollHealthContentToBottom() {
    const scrollableContainer = document.querySelector('.ai-helper-project-health-content.has-report');
    if (scrollableContainer) {
      scrollableContainer.scrollTop = scrollableContainer.scrollHeight;
    }
  }

  /**
   * Render an incoming streaming chunk. Split out of eventSource.onmessage
   * to keep it under ESLint's max-depth limit.
   * @param {HTMLElement} resultDiv - The report result container.
   * @param {AiHelperMarkdownParser} parser - Parser used to render the accumulated markdown.
   * @param {string} content - The full accumulated content so far.
   */
  function appendStreamingChunk(resultDiv, parser, content) {
    // Hide loader on first content
    const loader = resultDiv.querySelector('.ai-helper-loader');
    if (loader && loader.style.display !== 'none') {
      loader.style.display = 'none';
    }

    // Chart directives are never shown while the report is streaming (and
    // a directive line still being received stays hidden too).
    const strippedContent = AiHelperChartDirective.stripForStreaming(content);
    const formattedContent = parser.parse(strippedContent);
    const newHTML = '<div class="ai-helper-streaming-content">' +
      formattedContent +
      '<span class="ai-helper-cursor">|</span></div>';
    resultDiv.innerHTML = newHTML;

    // Auto-scroll to bottom to show new content
    scrollHealthContentToBottom();
  }

  /**
   * Update the health report history in the master-detail layout once
   * generation finishes. Split out of eventSource.onmessage to keep it
   * under ESLint's max-depth limit.
   */
  function refreshHealthReportHistory() {
    if (typeof window.updateHealthReportHistory !== 'function') {
      refreshProjectHealthMetadata();
      return;
    }

    setTimeout(() => {
      window.updateHealthReportHistory((masterDetailInstance) => {
        if (!masterDetailInstance) {
          refreshProjectHealthMetadata();
          return;
        }

        setTimeout(() => {
          const firstReportRow = document.querySelector('.ai-helper-report-row');
          if (firstReportRow) {
            masterDetailInstance.selectedReportId = null;
            masterDetailInstance.selectReport(firstReportRow);
          }
          refreshProjectHealthMetadata();
        }, 100);
      });
    }, 1000);
  }

  /**
   * Render the completed report once streaming finishes. Split out of
   * eventSource.onmessage to keep it under ESLint's max-depth limit.
   * @param {HTMLElement} resultDiv - The report result container.
   * @param {AiHelperMarkdownParser} parser - Parser used to render the final markdown.
   * @param {string} content - The full generated report content.
   * @param {number} [savedReportId] - The saved report's id from the
   *   health_report_saved SSE event. When present, the server-rendered
   *   report body (which carries the charts) is fetched and swapped in,
   *   and the export links are rebuilt for the saved report.
   * @returns {Promise<void>|undefined} The swap promise when a saved report
   *   id was given, undefined otherwise.
   */
  function finalizeStreamingContent(resultDiv, parser, content, savedReportId) {
    // Validate the result area's structure before touching the DOM, so a
    // failed guard leaves the page as it was instead of a finished-looking
    // pane whose history, export links and timestamp were never updated.
    hiddenFieldContainerOf(resultDiv);

    // Selecting another report while streaming replaces the whole detail
    // pane (AiHelperMasterDetail#renderReportDetail), detaching the result
    // area together with its content container, so the guard above still
    // passes. Rendering into the detached pane is pointless, and the
    // hidden-field lookup by id would overwrite the newly shown pane's
    // field. The report itself was saved on the server, so only the
    // history list is refreshed.
    if (!resultDiv.isConnected) {
      refreshHealthReportHistory();
      return;
    }

    // The client-rendered completion never shows chart directives either;
    // the charts arrive with the server-rendered swap below.
    const strippedContent = AiHelperChartDirective.stripForStreaming(content);
    const formattedContent = parser.parse(strippedContent);
    const finalHTML = '<div class="ai-helper-final-content">' +
      formattedContent + '</div>';
    resultDiv.innerHTML = finalHTML;

    // Store the markdown content in hidden field for PDF generation
    updateHiddenReportContent(resultDiv, content);

    // Update health report history in master-detail layout
    refreshHealthReportHistory();

    // Final scroll to bottom
    scrollHealthContentToBottom();

    if (savedReportId) {
      // The server-rendered body and the saved report's export links arrive
      // asynchronously. Adding the meta-tag based export links here too
      // would duplicate them.
      return swapInSavedReportContent(resultDiv, savedReportId);
    }

    // Add PDF export button after generation completes
    addPdfExportButton();

    // Refresh metadata (created timestamp) to reflect the regenerated report
    refreshProjectHealthMetadata();
    return undefined;
  }

  /**
   * Add the PDF/Markdown export links below the report, unless already present.
   */
  function addPdfExportButton() {
    const healthDiv = document.querySelector('.ai-helper-project-health');
    if (healthDiv) {
      // Check if PDF button already exists
      const existingPdfButton = healthDiv.querySelector('.other-formats');
      if (!existingPdfButton) {
        // Create other-formats paragraph
        const otherFormatsP = document.createElement('p');
        otherFormatsP.className = 'other-formats';

        // Get the export label and URLs from meta tags
        const exportLabel = document.querySelector('meta[name="export-label"]');
        const markdownUrl = document.querySelector('meta[name="markdown-export-url"]');
        const pdfUrl = document.querySelector('meta[name="pdf-export-url"]');

        const exportLabelText = exportLabel ? exportLabel.getAttribute('content') : 'Export to';
        const markdownUrlHref = markdownUrl ? markdownUrl.getAttribute('content') : '#';
        const pdfUrlHref = pdfUrl ? pdfUrl.getAttribute('content') : '#';

        otherFormatsP.appendChild(document.createTextNode(exportLabelText + ' '));

        const markdownSpan = document.createElement('span');
        const markdownLink = document.createElement('a');
        markdownLink.href = markdownUrlHref;
        markdownLink.className = 'text';
        markdownLink.id = 'ai-helper-markdown-export-link-dynamic';
        markdownLink.textContent = 'Markdown';
        markdownSpan.appendChild(markdownLink);
        otherFormatsP.appendChild(markdownSpan);

        otherFormatsP.appendChild(document.createTextNode(' '));

        const pdfSpan = document.createElement('span');
        const pdfLink = document.createElement('a');
        pdfLink.href = pdfUrlHref;
        pdfLink.className = 'pdf';
        pdfLink.id = 'ai-helper-pdf-export-link-dynamic';
        pdfLink.textContent = 'PDF';
        pdfSpan.appendChild(pdfLink);
        otherFormatsP.appendChild(pdfSpan);

        // Add the button to the health div
        healthDiv.appendChild(otherFormatsP);
      }
    }
  }

  /**
   * Remove the PDF/Markdown export links, if present.
   */
  function removePdfExportButton() {
    const healthDiv = document.querySelector('.ai-helper-project-health');
    if (healthDiv) {
      const otherFormatsP = healthDiv.querySelector('.other-formats');
      if (otherFormatsP) {
        otherFormatsP.remove();
      }
    }
  }

  /**
   * Find the `.ai-helper-project-health-content` ancestor that holds the
   * hidden report-content field, validating the result area itself first.
   * @param {HTMLElement} resultDiv - The report result container.
   * @returns {HTMLElement} The `.ai-helper-project-health-content` ancestor.
   * @throws {Error} If `resultDiv` is not an HTMLElement, or if it has no
   *   `.ai-helper-project-health-content` ancestor.
   */
  function hiddenFieldContainerOf(resultDiv) {
    if (!(resultDiv instanceof HTMLElement)) {
      throw new Error('the report result area must be an HTMLElement');
    }
    const contentContainer = resultDiv.closest('.ai-helper-project-health-content');
    if (!contentContainer) {
      throw new Error(
        'the report result area must have a .ai-helper-project-health-content ancestor',
      );
    }
    return contentContainer;
  }

  /**
   * Store the report's markdown content in a hidden field for later export,
   * creating the field inside the result area's `.ai-helper-project-health-content`
   * ancestor if it doesn't exist yet. That ancestor exists in every layout
   * that can generate a report (project overview, dashboard placeholder,
   * dashboard detail pane), unlike `.ai-helper-project-health`, which the
   * whole dashboard tab lacks.
   * @param {HTMLElement} resultDiv - The report result container.
   * @param {string} content - The report's raw markdown content.
   * @throws {Error} If `resultDiv` is not an HTMLElement or has no
   *   `.ai-helper-project-health-content` ancestor.
   */
  function updateHiddenReportContent(resultDiv, content) {
    const contentContainer = hiddenFieldContainerOf(resultDiv);
    let hiddenField = document.getElementById('ai-helper-health-report-content');
    if (!hiddenField) {
      // Create hidden field if it doesn't exist
      hiddenField = document.createElement('input');
      hiddenField.type = 'hidden';
      hiddenField.id = 'ai-helper-health-report-content';
      contentContainer.appendChild(hiddenField);
    }
    // Safely set the value to prevent XSS
    hiddenField.value = content;
  }

  /**
   * Submit the stored report content to the PDF export endpoint via a
   * generated form.
   * @param {MouseEvent} event - The export link's click event.
   */
  function handlePdfExport(event) {
    event.preventDefault();
    const hiddenField = document.getElementById('ai-helper-health-report-content');
    if (hiddenField && hiddenField.value) {
      // Create a form to submit the content
      const form = document.createElement('form');
      form.method = 'POST';
      form.action = event.target.href;

      const contentField = document.createElement('input');
      contentField.type = 'hidden';
      contentField.name = 'health_report_content';
      contentField.value = hiddenField.value;

      const csrfField = document.createElement('input');
      csrfField.type = 'hidden';
      csrfField.name = 'authenticity_token';
      csrfField.value = document.querySelector('meta[name="csrf-token"]').getAttribute('content');

      form.appendChild(contentField);
      form.appendChild(csrfField);
      document.body.appendChild(form);
      form.submit();
      document.body.removeChild(form);
    }
  }

  /**
   * Submit the stored report content to the Markdown export endpoint via a
   * generated form.
   * @param {MouseEvent} event - The export link's click event.
   */
  function handleMarkdownExport(event) {
    event.preventDefault();
    const hiddenField = document.getElementById('ai-helper-health-report-content');
    if (hiddenField && hiddenField.value) {
      // Create a form to submit the content
      const form = document.createElement('form');
      form.method = 'POST';
      form.action = event.target.href;

      const contentField = document.createElement('input');
      contentField.type = 'hidden';
      contentField.name = 'health_report_content';
      contentField.value = hiddenField.value;

      const csrfField = document.createElement('input');
      csrfField.type = 'hidden';
      csrfField.name = 'authenticity_token';
      csrfField.value = document.querySelector('meta[name="csrf-token"]').getAttribute('content');

      form.appendChild(contentField);
      form.appendChild(csrfField);
      document.body.appendChild(form);
      form.submit();
      document.body.removeChild(form);
    }
  }

/**
 * If a health report is already rendered in the DOM (e.g. after a page
 * reload), ensure its "has-report" styling and PDF export button are in
 * place. The rendered body stays exactly as the server produced it.
 */
function initializeExistingReportDisplay() {
  const resultDiv = document.getElementById('ai-helper-project-health-result');
  const contentDiv = document.querySelector('.ai-helper-project-health-content');

  if (resultDiv && resultDiv.classList.contains('ai-helper-final-content')) {
    // Ensure the has-report class is applied for existing content
    if (contentDiv && !contentDiv.classList.contains('has-report')) {
      contentDiv.classList.add('has-report');
    }

    addPdfExportButton();
  }
}

/**
 * Watch the project health container for DOM replacement (e.g. after
 * updateHealthReportHistory swaps content in) and re-apply the "has-report"
 * class and PDF export button whenever a report re-appears.
 */
function setupHealthReportObserver() {
  const observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(mutation) {
      if (mutation.type === 'childList') {
        // Check if the health report content was re-rendered
        const newResultDiv = document.getElementById('ai-helper-project-health-result');
        const newContentDiv = document.querySelector('.ai-helper-project-health-content');

        if (newResultDiv && newResultDiv.classList.contains('ai-helper-final-content')) {
          // Ensure proper classes and formatting
          if (newContentDiv && !newContentDiv.classList.contains('has-report')) {
            newContentDiv.classList.add('has-report');
          }

          // Ensure PDF button exists
          if (!document.querySelector('.other-formats')) {
            addPdfExportButton();
          }
        }
      }
    });
  });

  // Start observing the project health container
  const healthContainer = document.querySelector('.ai-helper-project-health');
  if (healthContainer) {
    observer.observe(healthContainer, { childList: true, subtree: true });
  }
}

// Make functions used by ai_helper_project_health_actions.js and
// ai_helper_project_health_swap.js (split out to keep this file under the
// max-lines ESLint limit; see ADR-027) globally available.
window.appendStreamingChunk = appendStreamingChunk;
window.finalizeStreamingContent = finalizeStreamingContent;
window.removePdfExportButton = removePdfExportButton;
window.handlePdfExport = handlePdfExport;
window.handleMarkdownExport = handleMarkdownExport;
window.hiddenFieldContainerOf = hiddenFieldContainerOf;

// handleGenerateProjectHealthClick and handleProjectHealthExportClick are
// defined in ai_helper_project_health_actions.js.

document.addEventListener('DOMContentLoaded', function() {

  // Set flag to indicate main script is loaded
  window.aiHelperProjectHealthLoaded = true;

  initializeExistingReportDisplay();
  setupHealthReportObserver();

  // Add event listeners to export links
  document.addEventListener('click', handleProjectHealthExportClick);

  // Only the streaming generation needs the Markdown parser. A missing parser
  // script is a page setup error, so let it surface instead of silently
  // skipping the initialization above.
  if (typeof AiHelperMarkdownParser === 'undefined') {
    throw new Error('AiHelperMarkdownParser is not loaded; the project health report cannot be generated.');
  }
  if (typeof AiHelperChartDirective === 'undefined') {
    throw new Error('AiHelperChartDirective is not loaded; chart directives cannot be stripped from the report.');
  }
  const parser = new AiHelperMarkdownParser();

  // Use event delegation so the handler survives DOM replacement
  // (e.g. after updateHealthReportHistory replaces the history container)
  document.addEventListener('click', function(e) {
    handleGenerateProjectHealthClick(e, parser);
  });
});

} // End guard against multiple script loading
