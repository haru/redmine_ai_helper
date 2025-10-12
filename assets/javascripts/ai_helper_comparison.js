// Health Report Comparison Analysis - Streaming Processing
if (!window.aiHelperComparisonInitialized) {
  window.aiHelperComparisonInitialized = true;

document.addEventListener('DOMContentLoaded', function() {
  const analyzeButton = document.getElementById('analyze-changes-button');

  if (!analyzeButton) return;

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

  analyzeButton.addEventListener('click', function(e) {
    e.preventDefault();

    // Close existing EventSource
    if (currentEventSource) {
      currentEventSource.close();
      currentEventSource = null;
    }

    const oldReportId = this.dataset.oldReportId;
    const newReportId = this.dataset.newReportId;
    const resultDiv = document.getElementById('ai-helper-comparison-analysis');

    if (!resultDiv) return;

    // Show loading state
    resultDiv.innerHTML = '<div class="ai-helper-loader"></div>';

    // Receive streaming via Server-Sent Events
    const url = this.href;
    currentEventSource = new EventSource(url);
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
        }

        if (data.choices && data.choices[0] && data.choices[0].finish_reason === 'stop') {
          eventSource.close();
          currentEventSource = null;

          // Render final content
          const formattedContent = parser.parse(content);
          resultDiv.innerHTML = '<div class="ai-helper-final-content">' +
            formattedContent + '</div>';
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
  });
});

}
