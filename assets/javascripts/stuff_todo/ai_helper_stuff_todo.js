// Guard against multiple script loading
if (!window.aiHelperStuffTodoInitialized) {
  window.aiHelperStuffTodoInitialized = true;

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

  let currentEventSource = null;

  /**
   * Open the stuff-todo modal and start streaming suggestions into it.
   */
  function openModal() {
    overlay.style.display = 'block';
    modal.style.display = 'block';
    body.innerHTML = '<div class="ai-helper-loader"></div>';
    streamStuffTodo();
  }

  /**
   * Close the stuff-todo modal and abort any in-flight streaming.
   */
  function closeModal() {
    overlay.style.display = 'none';
    modal.style.display = 'none';
    if (currentEventSource) {
      currentEventSource.close();
      currentEventSource = null;
    }
  }

  /**
   * Open an SSE connection to `stuffTodoUrl` and render the streamed
   * markdown content into the modal body as it arrives.
   */
  function streamStuffTodo() {
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

  // Event handler for the menu link added by Redmine's MenuManager
  if (menuLink) {
    menuLink.addEventListener('click', function(e) {
      e.preventDefault();
      openModal();
    });
  }

  closeBtn.addEventListener('click', function() {
    closeModal();
  });

  overlay.addEventListener('click', function() {
    closeModal();
  });

  // Close on Escape key
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && modal.style.display === 'block') {
      closeModal();
    }
  });
});

} // End guard against multiple script loading
