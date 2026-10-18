// Health Report Comparison Analysis - Streaming Processing
if (!window.aiHelperComparisonInitialized) {
  window.aiHelperComparisonInitialized = true;

  /**
   * Append a hidden input with the given name/value to a form.
   * @param {HTMLFormElement} form - The form to append the input to.
   * @param {string} name - The input's `name` attribute.
   * @param {string} value - The input's `value` attribute.
   */
  function appendHiddenInput(form, name, value) {
    const field = document.createElement('input');
    field.type = 'hidden';
    field.name = name;
    field.value = value;
    form.appendChild(field);
  }

  /**
   * Submit the comparison content (PDF or Markdown export) via a generated form.
   * @param {MouseEvent} event - The export link's click event.
   */
  function handleComparisonExport(event) {
    event.preventDefault();
    const hiddenField = document.getElementById('ai-helper-comparison-content');
    const oldReportIdField = document.getElementById('ai-helper-comparison-old-report-id');
    const newReportIdField = document.getElementById('ai-helper-comparison-new-report-id');

    if (!hiddenField || !hiddenField.value) {return;}

    const form = document.createElement('form');
    form.method = 'POST';
    form.action = event.target.href;

    appendHiddenInput(form, 'comparison_content', hiddenField.value);
    appendHiddenInput(form, 'old_report_id', oldReportIdField ? oldReportIdField.value : '');
    appendHiddenInput(form, 'new_report_id', newReportIdField ? newReportIdField.value : '');

    const csrfToken = document.querySelector('meta[name="csrf-token"]');
    appendHiddenInput(form, 'authenticity_token', csrfToken ? csrfToken.getAttribute('content') : '');

    document.body.appendChild(form);
    form.submit();
    document.body.removeChild(form);
  }

  /**
   * Render comparison markdown. Comparison reports cannot draw charts, so
   * directive lines become the explanatory message before parsing (R-012).
   * @param {AiHelperMarkdownParser} parser - The markdown parser.
   * @param {HTMLElement} resultDiv - The analysis container carrying the
   *   data-chart-unavailable-message attribute.
   * @param {string} text - The comparison markdown received so far.
   * @returns {string} The rendered HTML.
   * @throws {TypeError} When the container has no unavailable message.
   */
  function renderComparisonMarkdown(parser, resultDiv, text) {
    return parser.parse(
      AiHelperChartDirective.replaceForComparison(text, resultDiv.dataset.chartUnavailableMessage));
  }

  /**
   * Store the finished comparison content in the hidden field the export
   * links read from.
   * @param {string} content - The finished, un-rendered comparison markdown.
   */
  function updateComparisonContent(content) {
    const hiddenField = document.getElementById('ai-helper-comparison-content');
    if (hiddenField) {
      hiddenField.value = content;
    }
  }

  document.addEventListener('DOMContentLoaded', function() {
    const resultDiv = document.getElementById('ai-helper-comparison-analysis');
    if (!resultDiv) {return;}

    const analysisUrl = resultDiv.dataset.analysisUrl;
    if (!analysisUrl) {return;}

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

    let currentEventSource = null;

    /**
     * Open an SSE connection to the analysis endpoint and stream the
     * rendered comparison into the result panel, closing any prior stream.
     */
    function startAnalysis() {
      if (currentEventSource) {
        currentEventSource.close();
        currentEventSource = null;
      }

      // Hide export buttons during analysis
      const exportDiv = document.getElementById('ai-helper-comparison-export');
      if (exportDiv) {
        exportDiv.style.display = 'none';
      }

      // Show loading state
      resultDiv.innerHTML = '<div class="ai-helper-loader"></div>';

      // Receive streaming via Server-Sent Events
      currentEventSource = new EventSource(analysisUrl);
      const eventSource = currentEventSource;
      let content = '';
      const renderer = new AiHelperFrameRenderer(function() {
        // A newer analysis may have replaced this stream since scheduling.
        if (currentEventSource !== eventSource) {
          return;
        }
        const formattedContent = renderComparisonMarkdown(parser, resultDiv, content);
        resultDiv.innerHTML = '<div class="ai-helper-streaming-content">' +
          formattedContent +
          '<span class="ai-helper-cursor">|</span></div>';

        // Auto-scroll to bottom to show new content
        resultDiv.scrollTop = resultDiv.scrollHeight;
      });

      eventSource.onmessage = function(event) {
        // Read the payload once, outside the try, so only JSON.parse is
        // guarded and the logged payload is that saved value.
        const rawData = event.data;
        let data;
        try {
          data = JSON.parse(rawData);
        } catch (error) {
          // Only JSON.parse's SyntaxError is recoverable: log it and keep
          // receiving. Anything else is a real bug and must surface — the
          // former bare catch here swallowed render failures of the final
          // frame too, leaving the cursor frame stuck without exports or
          // console output (CRF-047).
          if (error instanceof SyntaxError) {
            console.error('Failed to parse comparison streaming event data:', error, rawData);
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
          currentEventSource = null;
          renderer.cancel();

          // Render final content. A failure here propagates: the exports
          // and the hidden field below depend on it.
          const formattedContent = renderComparisonMarkdown(parser, resultDiv, content);
          resultDiv.innerHTML = '<div class="ai-helper-final-content">' +
            formattedContent + '</div>';

          // Final scroll to bottom
          if (resultDiv) {
            resultDiv.scrollTop = resultDiv.scrollHeight;
          }

          // Store content in hidden field for export
          updateComparisonContent(content);

          // Show export buttons
          if (exportDiv) {
            exportDiv.style.display = 'block';
          }
        }
      };

      eventSource.onerror = function() {
        eventSource.close();
        currentEventSource = null;
        renderer.cancel();

        const errorMessage = document.querySelector('meta[name="i18n-error-message"]');
        const errorText = errorMessage ? errorMessage.getAttribute('content') : 'Error';
        resultDiv.innerHTML = '<div class="ai-helper-error">' + errorText + '</div>';
      };
    }

    // Add event listeners for export links
    document.addEventListener('click', function(event) {
      if (event.target.id === 'ai-helper-comparison-pdf-export-link') {
        handleComparisonExport(event);
      } else if (event.target.id === 'ai-helper-comparison-markdown-export-link') {
        handleComparisonExport(event);
      }
    });

    startAnalysis();
  });
}
