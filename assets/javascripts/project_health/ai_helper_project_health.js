// Guard against multiple script loading
if (!window.aiHelperProjectHealthInitialized) {
  window.aiHelperProjectHealthInitialized = true;

  function getProjectHealthMetadataConfig() {
    const urlMeta = document.querySelector('meta[name="ai-helper-project-health-metadata-url"]');
    const labelMeta = document.querySelector('meta[name="ai-helper-project-health-created-label"]');
    return {
      url: urlMeta ? urlMeta.getAttribute('content') : null,
      label: labelMeta ? labelMeta.getAttribute('content') : ''
    };
  }

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

  // Auto-scroll the streaming result container to the bottom. Split out to
  // keep the eventSource.onmessage handler under ESLint's max-depth limit.
  function scrollHealthContentToBottom() {
    const scrollableContainer = document.querySelector('.ai-helper-project-health-content.has-report');
    if (scrollableContainer) {
      scrollableContainer.scrollTop = scrollableContainer.scrollHeight;
    }
  }

  // Render an incoming streaming chunk. Split out of eventSource.onmessage
  // to keep it under ESLint's max-depth limit.
  function appendStreamingChunk(resultDiv, parser, content) {
    // Hide loader on first content
    const loader = resultDiv.querySelector('.ai-helper-loader');
    if (loader && loader.style.display !== 'none') {
      loader.style.display = 'none';
    }

    const formattedContent = parser.parse(content);
    const newHTML = '<div class="ai-helper-streaming-content">' +
      formattedContent +
      '<span class="ai-helper-cursor">|</span></div>';
    resultDiv.innerHTML = newHTML;

    // Auto-scroll to bottom to show new content
    scrollHealthContentToBottom();
  }

  // Update the health report history in the master-detail layout once
  // generation finishes. Split out of eventSource.onmessage to keep it
  // under ESLint's max-depth limit.
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

  // Render the completed report once streaming finishes. Split out of
  // eventSource.onmessage to keep it under ESLint's max-depth limit.
  function finalizeStreamingContent(resultDiv, parser, content) {
    const formattedContent = parser.parse(content);
    const finalHTML = '<div class="ai-helper-final-content">' +
      formattedContent + '</div>';
    resultDiv.innerHTML = finalHTML;

    // Store the markdown content in hidden field for PDF generation
    updateHiddenReportContent(content);

    // Update health report history in master-detail layout
    refreshHealthReportHistory();

    // Final scroll to bottom
    scrollHealthContentToBottom();

    // Add PDF export button after generation completes
    addPdfExportButton();

    // Refresh metadata (created timestamp) to reflect the regenerated report
    refreshProjectHealthMetadata();
  }

  // Function to add PDF export button after report generation
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

        otherFormatsP.innerHTML = exportLabelText + ' <span><a href="' + markdownUrlHref + '" class="text" id="ai-helper-markdown-export-link-dynamic">Markdown</a></span> <span><a href="' + pdfUrlHref + '" class="pdf" id="ai-helper-pdf-export-link-dynamic">PDF</a></span>';

        // Add the button to the health div
        healthDiv.appendChild(otherFormatsP);
      }
    }
  }

  // Function to remove PDF export button
  function removePdfExportButton() {
    const healthDiv = document.querySelector('.ai-helper-project-health');
    if (healthDiv) {
      const otherFormatsP = healthDiv.querySelector('.other-formats');
      if (otherFormatsP) {
        otherFormatsP.remove();
      }
    }
  }

  // Function to update hidden field with report content
  function updateHiddenReportContent(content) {
    let hiddenField = document.getElementById('ai-helper-health-report-content');
    if (!hiddenField) {
      // Create hidden field if it doesn't exist
      hiddenField = document.createElement('input');
      hiddenField.type = 'hidden';
      hiddenField.id = 'ai-helper-health-report-content';
      document.querySelector('.ai-helper-project-health').appendChild(hiddenField);
    }
    // Safely set the value to prevent XSS
    hiddenField.value = content;
  }

  // Function to handle PDF export with current content
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

  // Function to handle Markdown export with current content
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

document.addEventListener('DOMContentLoaded', function() {

  // Set flag to indicate main script is loaded
  window.aiHelperProjectHealthLoaded = true;

  // Wait for AiHelperMarkdownParser to be available
  let parser;
  try {
    if (typeof AiHelperMarkdownParser !== 'undefined') {
      parser = new AiHelperMarkdownParser();
    } else {
      return;
    }
  } catch {
    return;
  }

  // Check if report already exists and ensure proper initialization
  const resultDiv = document.getElementById('ai-helper-project-health-result');
  const contentDiv = document.querySelector('.ai-helper-project-health-content');

  if (resultDiv && resultDiv.classList.contains('ai-helper-final-content')) {
    // Ensure the has-report class is applied for existing content
    if (contentDiv && !contentDiv.classList.contains('has-report')) {
      contentDiv.classList.add('has-report');
    }

    // textilizable() honors Redmine's text_formatting setting, which may be
    // Textile and therefore breaks Markdown headings/tables. Re-parse the
    // raw Markdown stored in the hidden field to render consistently.
    const hiddenField = document.getElementById('ai-helper-health-report-content');
    if (hiddenField && hiddenField.value) {
      const formattedContent = parser.parse(hiddenField.value);
      resultDiv.innerHTML = '<div class="ai-helper-final-content">' + formattedContent + '</div>';
    }

    addPdfExportButton();
  }

  // Set up MutationObserver to watch for DOM changes and re-initialize as needed
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

  let currentEventSource = null; // Keep track of current EventSource

  // Use event delegation so the handler survives DOM replacement
  // (e.g. after updateHealthReportHistory replaces the history container)
  document.addEventListener('click', function(e) {
    const generateLink = e.target.closest('#ai-helper-generate-project-health-link');
    if (!generateLink) {
      return;
    }
    e.preventDefault();

    // Close any existing EventSource to prevent conflicts
    if (currentEventSource) {
      currentEventSource.close();
      currentEventSource = null;
    }

    // Get the result div that should already exist in the scrollable container
    const resultDiv = document.getElementById('ai-helper-project-health-result');

    // If no result div exists, something is wrong with the DOM structure
    if (!resultDiv) {
      console.error('No result div found for report generation. Please check the page structure.');
      alert('Error: Cannot find report display area. Please refresh the page.');
      return;
    }

    // Hide placeholder if it exists
    const placeholder = document.querySelector('.ai-helper-detail-placeholder');
    if (placeholder) {
      placeholder.style.display = 'none';
    }

    // Show the report detail container if it's hidden
    const reportDetail = document.querySelector('.ai-helper-health-report-detail');
    if (reportDetail && reportDetail.style.display === 'none') {
      reportDetail.style.display = 'block';
    }

    // Show loading state and add has-report class
    const contentContainer = resultDiv.closest('.ai-helper-project-health-content');
    resultDiv.innerHTML = '<div class="ai-helper-loader"></div>';
    if (contentContainer) {
      contentContainer.classList.add('has-report');
    }
    if (resultDiv.parentElement) {
      resultDiv.parentElement.classList.add('has-report');
    }

    // Remove existing PDF button during generation
    removePdfExportButton();

    const url = generateLink.href;

    // Create EventSource for streaming
    currentEventSource = new EventSource(url);
    const eventSource = currentEventSource;
    let content = '';

    eventSource.onmessage = function(event) {
      try {
        const data = JSON.parse(event.data);
        if (data.choices && data.choices[0] && data.choices[0].delta && data.choices[0].delta.content) {
          content += data.choices[0].delta.content;
          if (resultDiv) {
            appendStreamingChunk(resultDiv, parser, content);
          }
        }

        if (data.choices && data.choices[0] && data.choices[0].finish_reason === 'stop') {
          eventSource.close();
          currentEventSource = null;
          if (resultDiv) {
            finalizeStreamingContent(resultDiv, parser, content);
          }
        }
      } catch {
        // Silently handle parsing errors
      }
    };

    eventSource.onerror = function() {
      eventSource.close();
      currentEventSource = null;
      if (resultDiv) {
        const errorMessage = document.querySelector('meta[name="error-message"]');
        const errorText = errorMessage ? errorMessage.getAttribute('content') : 'Error';
        resultDiv.innerHTML = '<div class="ai-helper-error">' + errorText + '</div>';

        // Ensure content container is visible even on error
        const contentContainer = resultDiv.closest('.ai-helper-project-health-content');
        if (contentContainer) {
          contentContainer.style.display = 'block';
        }
      }
      // Remove PDF button if it exists on error
      removePdfExportButton();
    };
  });

  // Add event listeners to export links
  document.addEventListener('click', function(event) {
    if (event.target.id === 'ai-helper-pdf-export-link' || event.target.id === 'ai-helper-pdf-export-link-dynamic') {
      handlePdfExport(event);
    } else if (event.target.id === 'ai-helper-markdown-export-link' || event.target.id === 'ai-helper-markdown-export-link-dynamic') {
      handleMarkdownExport(event);
    }
  });
});

// --- extracted from project/_health_report_detail_pane.html.erb and
// project/_health_report_show.html.erb (near-duplicate Markdown re-parse +
// export wiring, unified here) ---
document.addEventListener('DOMContentLoaded', function() {
  const hiddenField = document.getElementById('ai-helper-health-report-content');
  const resultDiv = document.getElementById('ai-helper-project-health-result');
  if (!hiddenField || !resultDiv) { return; }
  if (typeof AiHelperMarkdownParser === 'undefined') { return; }
  const content = hiddenField.value;
  if (!content) { return; }
  const parser = new AiHelperMarkdownParser();
  const formattedContent = parser.parse(content);
  resultDiv.innerHTML = '<div class="ai-helper-final-content">' + formattedContent + '</div>';

  // detail_pane variant: build and submit a form dynamically.
  const detailExportLink = document.getElementById('ai-helper-markdown-export-detail');
  if (detailExportLink) {
    detailExportLink.addEventListener('click', function(e) {
      e.preventDefault();
      const markdownContent = hiddenField.value;
      if (!markdownContent) { return; }

      const detailPane = document.querySelector('.ai-helper-health-report-detail[data-config]');
      const config = detailPane ? JSON.parse(detailPane.dataset.config || '{}') : {};

      const form = document.createElement('form');
      form.method = 'POST';
      form.action = config.markdownExportUrl;

      const contentField = document.createElement('input');
      contentField.type = 'hidden';
      contentField.name = 'health_report_content';
      contentField.value = markdownContent;

      const csrfToken = document.querySelector('meta[name="csrf-token"]');
      if (csrfToken) {
        const tokenField = document.createElement('input');
        tokenField.type = 'hidden';
        tokenField.name = 'authenticity_token';
        tokenField.value = csrfToken.getAttribute('content');
        form.appendChild(tokenField);
      }

      form.appendChild(contentField);
      document.body.appendChild(form);
      form.submit();
      document.body.removeChild(form);
    });
  }

  // show variant: submit the pre-rendered export form.
  const showExportLink = document.getElementById('export-markdown-link');
  const showExportForm = document.getElementById('markdown-export-form');
  if (showExportLink && showExportForm) {
    showExportLink.addEventListener('click', function(e) {
      e.preventDefault();
      showExportForm.submit();
    });
  }
});

} // End guard against multiple script loading
