// Health Report Comparison Analysis - Streaming Processing
if (!window.aiHelperComparisonInitialized) {
  window.aiHelperComparisonInitialized = true;

  document.addEventListener('DOMContentLoaded', function() {
    const resultDiv = document.getElementById('ai-helper-comparison-analysis');
    if (!resultDiv) return;

    const analysisUrl = resultDiv.dataset.analysisUrl;
    if (!analysisUrl) return;

    let parser;
    try {
      if (typeof AiHelperMarkdownParser !== 'undefined') {
        parser = new AiHelperMarkdownParser();
      } else {
        return;
      }
    } catch (error) {
      return;
    }

    let currentEventSource = null;

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

      eventSource.onmessage = function(event) {
        try {
          const data = JSON.parse(event.data);

          if (data.choices && data.choices[0] && data.choices[0].delta && data.choices[0].delta.content) {
            content += data.choices[0].delta.content;

            // Hide loader on first content
            const loader = resultDiv.querySelector('.ai-helper-loader');
            if (loader && loader.style.display !== 'none') {
              loader.style.display = 'none';
            }

            // Render streaming content
            const formattedContent = parser.parse(content);
            resultDiv.innerHTML = '<div class="ai-helper-streaming-content">' +
              formattedContent +
              '<span class="ai-helper-cursor">|</span></div>';

            // Auto-scroll to bottom to show new content
            if (resultDiv) {
              resultDiv.scrollTop = resultDiv.scrollHeight;
            }
          }

          if (data.choices && data.choices[0] && data.choices[0].finish_reason === 'stop') {
            eventSource.close();
            currentEventSource = null;

            // Render final content
            const formattedContent = parser.parse(content);
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
        } catch (error) {
          // Error handling done in onerror
        }
      };

      eventSource.onerror = function(event) {
        eventSource.close();
        currentEventSource = null;

        const errorMessage = document.querySelector('meta[name="i18n-error-message"]');
        const errorText = errorMessage ? errorMessage.getAttribute('content') : 'Error';
        resultDiv.innerHTML = '<div class="ai-helper-error">' + errorText + '</div>';
      };
    }

    // Function to update hidden field with comparison content
    function updateComparisonContent(content) {
      const hiddenField = document.getElementById('ai-helper-comparison-content');
      if (hiddenField) {
        hiddenField.value = content;
      }
    }

    // Function to handle PDF export
    function handlePdfExport(event) {
      event.preventDefault();
      const hiddenField = document.getElementById('ai-helper-comparison-content');
      const oldReportIdField = document.getElementById('ai-helper-comparison-old-report-id');
      const newReportIdField = document.getElementById('ai-helper-comparison-new-report-id');

      if (hiddenField && hiddenField.value) {
        const form = document.createElement('form');
        form.method = 'POST';
        form.action = event.target.href;

        const contentField = document.createElement('input');
        contentField.type = 'hidden';
        contentField.name = 'comparison_content';
        contentField.value = hiddenField.value;

        const oldIdField = document.createElement('input');
        oldIdField.type = 'hidden';
        oldIdField.name = 'old_report_id';
        oldIdField.value = oldReportIdField ? oldReportIdField.value : '';

        const newIdField = document.createElement('input');
        newIdField.type = 'hidden';
        newIdField.name = 'new_report_id';
        newIdField.value = newReportIdField ? newReportIdField.value : '';

        const csrfField = document.createElement('input');
        csrfField.type = 'hidden';
        csrfField.name = 'authenticity_token';
        const csrfToken = document.querySelector('meta[name="csrf-token"]');
        if (csrfToken) {
          csrfField.value = csrfToken.getAttribute('content');
        }

        form.appendChild(contentField);
        form.appendChild(oldIdField);
        form.appendChild(newIdField);
        form.appendChild(csrfField);
        document.body.appendChild(form);
        form.submit();
        document.body.removeChild(form);
      }
    }

    // Function to handle Markdown export
    function handleMarkdownExport(event) {
      event.preventDefault();
      const hiddenField = document.getElementById('ai-helper-comparison-content');
      const oldReportIdField = document.getElementById('ai-helper-comparison-old-report-id');
      const newReportIdField = document.getElementById('ai-helper-comparison-new-report-id');

      if (hiddenField && hiddenField.value) {
        const form = document.createElement('form');
        form.method = 'POST';
        form.action = event.target.href;

        const contentField = document.createElement('input');
        contentField.type = 'hidden';
        contentField.name = 'comparison_content';
        contentField.value = hiddenField.value;

        const oldIdField = document.createElement('input');
        oldIdField.type = 'hidden';
        oldIdField.name = 'old_report_id';
        oldIdField.value = oldReportIdField ? oldReportIdField.value : '';

        const newIdField = document.createElement('input');
        newIdField.type = 'hidden';
        newIdField.name = 'new_report_id';
        newIdField.value = newReportIdField ? newReportIdField.value : '';

        const csrfField = document.createElement('input');
        csrfField.type = 'hidden';
        csrfField.name = 'authenticity_token';
        const csrfToken = document.querySelector('meta[name="csrf-token"]');
        if (csrfToken) {
          csrfField.value = csrfToken.getAttribute('content');
        }

        form.appendChild(contentField);
        form.appendChild(oldIdField);
        form.appendChild(newIdField);
        form.appendChild(csrfField);
        document.body.appendChild(form);
        form.submit();
        document.body.removeChild(form);
      }
    }

    // Add event listeners for export links
    document.addEventListener('click', function(event) {
      if (event.target.id === 'ai-helper-comparison-pdf-export-link') {
        handlePdfExport(event);
      } else if (event.target.id === 'ai-helper-comparison-markdown-export-link') {
        handleMarkdownExport(event);
      }
    });

    startAnalysis();
  });
}
