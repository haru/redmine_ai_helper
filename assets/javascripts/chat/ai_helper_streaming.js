// SSE (Server-Sent Events) parsing and the AiHelper streaming methods that
// consume it. Split out of ai_helper.js to keep that file under the
// max-lines ESLint limit (see ADR-027). A classic script can't split a
// single class body across files, so this file extends AiHelper's
// static/prototype surface after the class is declared instead — same
// behavior as if these were defined inline in the class body. Must load
// after ai_helper.js (which declares `window.AiHelper`).

// Handles a `data: ` line for the `interactive_options` SSE event. Split out
// of parseSSELines() to keep it under ESLint's max-depth limit.
AiHelper.handleInteractiveOptionsData = function (dataStr, onInteractiveOptionsCallback) {
  try {
    const data = JSON.parse(dataStr);
    if (onInteractiveOptionsCallback && data.choices) {
      onInteractiveOptionsCallback(data.choices);
    }
  } catch (e) {
    console.error('Parse error for interactive_options:', e);
  }
};

// Handles a `data: ` line for a regular content/completion SSE event.
// Returns the updated fullResponse. Split out of parseSSELines() to keep it
// under ESLint's max-depth limit.
AiHelper.handleContentData = function (dataStr, response, onContentCallback, onCompleteCallback) {
  try {
    const data = JSON.parse(dataStr);
    const content = data.choices && data.choices[0]?.delta?.content;
    if (content) {
      response += content;
      if (onContentCallback) {
        onContentCallback(content, response);
      }
    }
    if (data.choices && data.choices[0]?.finish_reason === 'stop' && onCompleteCallback) {
      onCompleteCallback(response);
    }
  } catch (e) {
    console.error('Parse error:', e);
  }
  return response;
};

AiHelper.parseSSELines = function (lines, pendingEventType, fullResponse, onContentCallback, onCompleteCallback, onInteractiveOptionsCallback) {
  let eventType = pendingEventType;
  let response = fullResponse;

  for (const line of lines) {
    if (line.startsWith('event: ')) {
      eventType = line.substring('event: '.length).trim();
    } else if (line.startsWith('data: ')) {
      const dataStr = line.substring('data: '.length).trim();
      if (eventType === 'interactive_options') {
        AiHelper.handleInteractiveOptionsData(dataStr, onInteractiveOptionsCallback);
      } else {
        response = AiHelper.handleContentData(dataStr, response, onContentCallback, onCompleteCallback);
      }
      eventType = null;
    } else if (line === '') {
      if (eventType !== null) {
        eventType = null;
      }
    }
  }

  return { eventType, fullResponse: response };
};

Object.assign(AiHelper.prototype, {
  handleSSEStream(xhr, onContentCallback, onCompleteCallback, onInteractiveOptionsCallback) {
    let fullResponse = '';
    let buffer = '';
    let lastProcessedIndex = 0;
    let pendingEventType = null;

    xhr.onprogress = function () {
      const text = xhr.responseText.substring(lastProcessedIndex);
      lastProcessedIndex = xhr.responseText.length;
      buffer += text;

      const lines = buffer.split('\n');
      buffer = lines.pop();

      const result = AiHelper.parseSSELines(
        lines, pendingEventType, fullResponse,
        onContentCallback, onCompleteCallback, onInteractiveOptionsCallback
      );
      pendingEventType = result.eventType;
      fullResponse = result.fullResponse;
    };
  },

  generateSummaryStream(generateSummaryUrl, summaryErrorText) {
    const summaryArea = document.getElementById('ai-helper-summary-area');
    const url = generateSummaryUrl;

    // Set up streaming content area
    const streamingContent = document.createElement('div');
    streamingContent.id = 'ai-helper-streaming-summary';
    streamingContent.style.padding = '10px';
    streamingContent.style.marginTop = '10px';
    streamingContent.style.whiteSpace = 'pre-wrap';

    const loader = document.createElement('div');
    loader.className = 'ai-helper-loader';

    summaryArea.innerHTML = '';
    summaryArea.appendChild(loader);
    summaryArea.appendChild(streamingContent);

    const xhr = new XMLHttpRequest();
    xhr.open('POST', url, true);
    xhr.setRequestHeader('Content-Type', 'application/json');

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    if (csrfToken) {
      xhr.setRequestHeader('X-CSRF-Token', csrfToken);
    }

    xhr.responseType = 'text';

    // Use the common SSE handler
    this.handleSSEStream(xhr,
      // onContentCallback
      function(_content, fullResponse) {
        streamingContent.textContent = fullResponse;

        // Hide loader on first content
        if (loader.style.display !== 'none') {
          loader.style.display = 'none';
        }
      },
      // onCompleteCallback
      function(_fullResponse) {
        // Reload the summary display to show cached version
        setTimeout(() => {
          getSummary();
        }, 1000);
      }
    );

    xhr.onerror = function () {
      loader.style.display = 'none';
      streamingContent.textContent = summaryErrorText;
    };

    xhr.onload = function () {
      if (xhr.status !== 200) {
        loader.style.display = 'none';
        streamingContent.textContent = `Error: ${xhr.status} ${xhr.statusText}`;
      }
    };

    xhr.send('{}');
  },

  generateReplyStream(generateReplyUrl, instructions, errorText, applyButtonText, copyButtonText) {
    const replyArea = document.getElementById('ai-helper-generate_reply-area');
    replyArea.style.display = '';

    // Initialize streaming response area
    const streamingContent = document.createElement('div');
    streamingContent.id = 'ai-helper-streaming-reply';

    const loader = document.createElement('div');
    loader.className = 'ai-helper-loader';

    replyArea.innerHTML = '';
    replyArea.appendChild(loader);
    replyArea.appendChild(streamingContent);

    const xhr = new XMLHttpRequest();
    xhr.open('POST', generateReplyUrl, true);
    xhr.setRequestHeader('Content-Type', 'application/json');

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    if (csrfToken) {
      xhr.setRequestHeader('X-CSRF-Token', csrfToken);
    }

    xhr.responseType = 'text';

    // Use the common SSE handler
    this.handleSSEStream(xhr,
      // onContentCallback
      function(_content, fullResponse) {
        streamingContent.textContent = fullResponse;

        // Hide loader on first content
        if (loader.style.display !== 'none') {
          loader.style.display = 'none';
        }
      },
      // onCompleteCallback
      function(fullResponse) {
        // Create apply button
        const applyButton = document.createElement('button');
        applyButton.type = 'button';
        applyButton.className = 'ai-helper-reply-apply-btn';
        applyButton.textContent = applyButtonText;
        applyButton.onclick = function(e) {
          e.preventDefault();
          const issueNotes = document.getElementById("issue_notes");
          if (issueNotes) {
            issueNotes.value = fullResponse;
          }
          return false;
        };

        // Create copy link
        const copyLink = document.createElement('a');
        copyLink.href = '#';
        copyLink.className = 'icon icon-copy-link';
        copyLink.innerHTML = copyButtonText;
        copyLink.onclick = function(e) {
          e.preventDefault();
          navigator.clipboard.writeText(fullResponse);
          return false;
        };

        replyArea.appendChild(applyButton);
        replyArea.appendChild(copyLink);
      }
    );

    xhr.onerror = function () {
      loader.style.display = 'none';
      streamingContent.textContent = errorText;
    };

    xhr.onload = function () {
      if (xhr.status !== 200) {
        loader.style.display = 'none';
        streamingContent.textContent = `Error: ${xhr.status} ${xhr.statusText}`;
      }
    };

    xhr.send(JSON.stringify({ instructions: instructions }));
  },

  generateWikiSummaryStream(generateSummaryUrl, summaryErrorText) {
    const summaryArea = document.getElementById('ai-helper-wiki-summary-area');

    // Set up streaming content area
    const streamingContent = document.createElement('div');
    streamingContent.id = 'ai-helper-streaming-wiki-summary';
    streamingContent.style.padding = '10px';
    streamingContent.style.marginTop = '10px';
    streamingContent.style.whiteSpace = 'pre-wrap';

    const loader = document.createElement('div');
    loader.className = 'ai-helper-loader';

    summaryArea.innerHTML = '';
    summaryArea.appendChild(loader);
    summaryArea.appendChild(streamingContent);

    const xhr = new XMLHttpRequest();
    xhr.open('POST', generateSummaryUrl, true);
    xhr.setRequestHeader('Content-Type', 'application/json');

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    if (csrfToken) {
      xhr.setRequestHeader('X-CSRF-Token', csrfToken);
    }

    xhr.responseType = 'text';

    // Use the common SSE handler
    this.handleSSEStream(xhr,
      // onContentCallback
      function(_content, fullResponse) {
        streamingContent.textContent = fullResponse;

        // Hide loader on first content
        if (loader.style.display !== 'none') {
          loader.style.display = 'none';
        }
      },
      // onCompleteCallback
      function(_fullResponse) {
        // Reload the summary display to show cached version
        setTimeout(() => {
          getWikiSummary();
        }, 1000);
      }
    );

    xhr.onerror = function () {
      loader.style.display = 'none';
      streamingContent.textContent = summaryErrorText;
    };

    xhr.onload = function () {
      if (xhr.status !== 200) {
        loader.style.display = 'none';
        streamingContent.textContent = `Error: ${xhr.status} ${xhr.statusText}`;
      }
    };

    xhr.send('{}');
  },
});
