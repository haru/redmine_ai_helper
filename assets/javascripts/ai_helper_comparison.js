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

    startAnalysis();
  });
}
