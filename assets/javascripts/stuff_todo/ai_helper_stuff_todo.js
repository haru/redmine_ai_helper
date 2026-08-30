// Guard against multiple script loading
if (!window.aiHelperStuffTodoInitialized) {
  window.aiHelperStuffTodoInitialized = true;

  let currentEventSource = null;

  /**
   * Open an SSE connection to `stuffTodoUrl` and render the streamed
   * markdown content into `body` as it arrives.
   * @param {string} stuffTodoUrl - SSE endpoint to stream suggestions from.
   * @param {Element|null} errorMeta - Meta tag holding the localized error message.
   * @param {object} parser - Markdown parser used to render streamed content.
   * @param {HTMLElement} body - Modal body element to render content into.
   * @returns {void}
   */
  function streamStuffTodo(stuffTodoUrl, errorMeta, parser, body) {
    if (currentEventSource) {
      currentEventSource.close();
      currentEventSource = null;
    }

    currentEventSource = new EventSource(stuffTodoUrl);
    const eventSource = currentEventSource;
    let content = '';

    eventSource.onmessage = function(event) {
      try {
        const data = JSON.parse(event.data);
        if (data.choices && data.choices[0] && data.choices[0].delta && data.choices[0].delta.content) {
          content += data.choices[0].delta.content;

          // Hide loader on first content
          const loader = body.querySelector('.ai-helper-loader');
          if (loader && loader.style.display !== 'none') {
            loader.style.display = 'none';
          }

          const formattedContent = parser.parse(content);
          body.innerHTML = '<div class="ai-helper-streaming-content">' +
            formattedContent +
            '<span class="ai-helper-cursor">|</span></div>';

          // Auto-scroll to bottom
          body.scrollTop = body.scrollHeight;
        }

        if (data.choices && data.choices[0] && data.choices[0].finish_reason === 'stop') {
          eventSource.close();
          currentEventSource = null;

          const formattedContent = parser.parse(content);
          body.innerHTML = '<div class="ai-helper-final-content">' +
            formattedContent + '</div>';
        }
      } catch {
        // Silently handle parsing errors
      }
    };

    eventSource.onerror = function() {
      eventSource.close();
      currentEventSource = null;
      const errorText = errorMeta ? errorMeta.getAttribute('content') : 'Error';
      body.innerHTML = '<div class="ai-helper-error">' + errorText + '</div>';
    };
  }

  /**
   * Open the stuff-todo modal and start streaming suggestions into it.
   * @param {HTMLElement} overlay - Modal overlay element to show.
   * @param {HTMLElement} modal - Modal element to show.
   * @param {HTMLElement} body - Modal body element to reset and stream content into.
   * @param {string} stuffTodoUrl - SSE endpoint to stream suggestions from.
   * @param {Element|null} errorMeta - Meta tag holding the localized error message.
   * @param {object} parser - Markdown parser used to render streamed content.
   * @returns {void}
   */
  function openStuffTodoModal(overlay, modal, body, stuffTodoUrl, errorMeta, parser) {
    overlay.style.display = 'block';
    modal.style.display = 'block';
    body.innerHTML = '<div class="ai-helper-loader"></div>';
    streamStuffTodo(stuffTodoUrl, errorMeta, parser, body);
  }

  /**
   * Close the stuff-todo modal and abort any in-flight streaming.
   * @param {HTMLElement} overlay - Modal overlay element to hide.
   * @param {HTMLElement} modal - Modal element to hide.
   * @returns {void}
   */
  function closeStuffTodoModal(overlay, modal) {
    overlay.style.display = 'none';
    modal.style.display = 'none';
    if (currentEventSource) {
      currentEventSource.close();
      currentEventSource = null;
    }
  }

  document.addEventListener('DOMContentLoaded', function() {

    // Retrieve configuration from meta tags
    const urlMeta = document.querySelector('meta[name="ai-helper-stuff-todo-url"]');
    const errorMeta = document.querySelector('meta[name="ai-helper-stuff-todo-error"]');

    // Hide the menu link on non-project pages where meta tag is not present
    const menuLink = document.getElementById('ai-helper-stuff-todo-link');
    if (!urlMeta) {
      if (menuLink) {
        menuLink.closest('li').style.display = 'none';
      }
      return;
    }

    const stuffTodoUrl = urlMeta.getAttribute('content');
    // Show only the link element itself (minimal change).
    // Avoid touching parent <li> or extra logic — just ensure the anchor is visible.
    if (menuLink) {
      menuLink.style.display = 'inline-block';
    }

    // Initialize markdown parser
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

    // Get modal elements from server-rendered HTML (ERB template)
    const overlay = document.getElementById('ai-helper-stuff-todo-overlay');
    const modal = document.getElementById('ai-helper-stuff-todo-modal');
    const closeBtn = document.getElementById('ai-helper-stuff-todo-close');
    const body = document.getElementById('ai-helper-stuff-todo-body');

    // Exit if modal elements are not found (should not happen if template is rendered correctly)
    if (!overlay || !modal || !closeBtn || !body) {
      return;
    }

    // Event handler for the menu link added by Redmine's MenuManager
    if (menuLink) {
      menuLink.addEventListener('click', function(e) {
        e.preventDefault();
        openStuffTodoModal(overlay, modal, body, stuffTodoUrl, errorMeta, parser);
      });
    }

    closeBtn.addEventListener('click', function() {
      closeStuffTodoModal(overlay, modal);
    });

    overlay.addEventListener('click', function() {
      closeStuffTodoModal(overlay, modal);
    });

    // Close on Escape key
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape' && modal.style.display === 'block') {
        closeStuffTodoModal(overlay, modal);
      }
    });
  });

} // End guard against multiple script loading
