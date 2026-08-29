// Click handlers for generating and exporting a project health report. Split
// out of ai_helper_project_health.js to keep that file under the max-lines
// ESLint limit (see ADR-027). Relies on helpers declared there
// (removePdfExportButton, appendStreamingChunk, finalizeStreamingContent,
// handlePdfExport, handleMarkdownExport) as globals, so must load after
// ai_helper_project_health.js.

let currentProjectHealthEventSource = null; // Keep track of current EventSource

/**
 * Handle a click on the "generate project health report" link (via event
 * delegation, so it survives DOM replacement): start (or restart) an
 * EventSource-based streaming request and render the result as it arrives.
 * @param {MouseEvent} e - The click event.
 * @param {AiHelperMarkdownParser} parser - The Markdown parser instance.
 */
function handleGenerateProjectHealthClick(e, parser) {
  const generateLink = e.target.closest('#ai-helper-generate-project-health-link');
  if (!generateLink) {
    return;
  }
  e.preventDefault();

  // Close any existing EventSource to prevent conflicts
  if (currentProjectHealthEventSource) {
    currentProjectHealthEventSource.close();
    currentProjectHealthEventSource = null;
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
  currentProjectHealthEventSource = new EventSource(url);
  const eventSource = currentProjectHealthEventSource;
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
        currentProjectHealthEventSource = null;
        if (resultDiv) {
          finalizeStreamingContent(resultDiv, parser, content);
        }
      }
    } catch (error) {
      console.error('Failed to parse project health streaming event data:', error, event.data);
    }
  };

  eventSource.onerror = function() {
    eventSource.close();
    currentProjectHealthEventSource = null;
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
}

/**
 * Handle a click on a PDF or Markdown export link for the project health
 * report, dispatching to the matching export handler.
 * @param {MouseEvent} event - The click event.
 */
function handleProjectHealthExportClick(event) {
  if (event.target.id === 'ai-helper-pdf-export-link' || event.target.id === 'ai-helper-pdf-export-link-dynamic') {
    handlePdfExport(event);
  } else if (event.target.id === 'ai-helper-markdown-export-link' || event.target.id === 'ai-helper-markdown-export-link-dynamic') {
    handleMarkdownExport(event);
  }
}

// Make functions used by ai_helper_project_health.js globally available.
window.handleGenerateProjectHealthClick = handleGenerateProjectHealthClick;
window.handleProjectHealthExportClick = handleProjectHealthExportClick;
