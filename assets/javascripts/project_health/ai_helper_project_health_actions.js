// Click handlers for generating and exporting a project health report. Split
// out of ai_helper_project_health.js to keep that file under the max-lines
// ESLint limit (see ADR-027). Relies on helpers declared there
// (removePdfExportButton, appendStreamingChunk, finalizeStreamingContent,
// handlePdfExport, handleMarkdownExport) as globals, so must load after
// ai_helper_project_health.js.

let currentProjectHealthEventSource = null; // Keep track of current EventSource

/**
 * Remove the previous report's details from a dashboard detail pane before
 * a new generation starts, so stale metadata, edit UI, notices, and export
 * links of the previously selected report never mix with the new stream.
 * The removal is permanent: if the generation errors, the elements are not
 * restored. The result area and its `.ai-helper-health-report-view` wrapper
 * are un-hidden: the wrapper is hidden while the edit form is open and the
 * area itself while the original is shown, so leaving either hidden would
 * render the loader and the stream into an invisible element. Outside a
 * detail pane (project overview, dashboard placeholder) this is a no-op.
 * @param {HTMLElement} resultDiv - The report result container.
 */
function clearPreviousReportDetails(resultDiv) {
  const reportBody = resultDiv.closest('.ai-helper-health-report-body');
  if (!reportBody) {
    return;
  }

  reportBody.querySelectorAll(
    '.ai-helper-health-report-meta, .contextual, .ai-helper-health-report-edit-form, ' +
    '.ai-helper-health-report-original, .flash, .other-formats',
  ).forEach((element) => element.remove());

  const showOriginalLink = reportBody.querySelector('.ai-helper-health-report-show-original');
  if (showOriginalLink) {
    // Both toggle links live in one <p> (see
    // app/views/ai_helper/project/_health_report_body.html.erb:38-42),
    // so removing the parent takes the "show current" link with it.
    showOriginalLink.parentElement.remove();
  }

  // The result area is hidden while the original report is shown, and its
  // whole view is hidden while the edit form is open.
  resultDiv.hidden = false;
  const view = reportBody.querySelector('.ai-helper-health-report-view');
  if (view) {
    view.hidden = false;
  }
}

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

  // Drop the previous report's details so the new generation starts clean,
  // and un-hide the view so the loader below is actually visible (no-op in
  // the project overview and the dashboard placeholder, which have no
  // detail pane).
  clearPreviousReportDetails(resultDiv);

  // Show loading state and add has-report class
  resultDiv.innerHTML = '<div class="ai-helper-loader"></div>';
  const contentContainer = resultDiv.closest('.ai-helper-project-health-content');
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
  // The id of the report the server saved for this generation, delivered
  // via a named SSE event before the stop chunk. Used to swap in the
  // server-rendered body when the stream finishes.
  let savedReportId = null;
  eventSource.addEventListener('health_report_saved', function(event) {
    savedReportId = JSON.parse(event.data).report_id;
  });
  const renderer = new AiHelperFrameRenderer(function() {
    // A newer generation may have replaced this stream since scheduling.
    if (currentProjectHealthEventSource !== eventSource) {
      return;
    }
    appendStreamingChunk(resultDiv, parser, content);
  });

  eventSource.onmessage = function(event) {
    // Read the payload once, outside the try, so only JSON.parse is guarded.
    const rawData = event.data;
    let data;
    try {
      data = JSON.parse(rawData);
    } catch (error) {
      // Only JSON.parse's SyntaxError is recoverable: log it and keep
      // receiving. Anything else is a real bug and must surface.
      if (error instanceof SyntaxError) {
        console.error('Failed to parse project health streaming event data:', error, rawData);
        return;
      }
      throw error;
    }

    if (data.choices && data.choices[0] && data.choices[0].delta && data.choices[0].delta.content) {
      content += data.choices[0].delta.content;
      renderer.schedule();
    }

    if (data.choices && data.choices[0] && data.choices[0].finish_reason === 'stop') {
      eventSource.close();
      currentProjectHealthEventSource = null;
      renderer.cancel();
      finalizeStreamingContent(resultDiv, parser, content, savedReportId);
    }
  };

  eventSource.onerror = function() {
    eventSource.close();
    currentProjectHealthEventSource = null;
    renderer.cancel();
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
