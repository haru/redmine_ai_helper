// Guard against multiple script loading
if (!window.aiHelperStuffTodoInitialized) {
  window.aiHelperStuffTodoInitialized = true;

document.addEventListener('DOMContentLoaded', function() {

  // Retrieve configuration from meta tags
  const urlMeta = document.querySelector('meta[name="ai-helper-stuff-todo-url"]');
  const titleMeta = document.querySelector('meta[name="ai-helper-stuff-todo-title"]');
  const menuLabelMeta = document.querySelector('meta[name="ai-helper-stuff-todo-menu-label"]');
  const loadingMeta = document.querySelector('meta[name="ai-helper-stuff-todo-loading"]');
  const errorMeta = document.querySelector('meta[name="ai-helper-stuff-todo-error"]');

  if (!urlMeta) {
    return;
  }

  const stuffTodoUrl = urlMeta.getAttribute('content');
  const modalTitle = titleMeta ? titleMeta.getAttribute('content') : 'To Do Suggestions';
  const menuLabel = menuLabelMeta ? menuLabelMeta.getAttribute('content') : 'To Do';
  const loadingText = loadingMeta ? loadingMeta.getAttribute('content') : 'Loading...';
  const errorText = errorMeta ? errorMeta.getAttribute('content') : 'An error occurred';

  // Initialize markdown parser
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

  // Inject the menu link into the top menu
  const loggedAs = document.getElementById('loggedas');
  if (!loggedAs) {
    return;
  }

  const menuLink = document.createElement('a');
  menuLink.id = 'ai-helper-stuff-todo-link';
  menuLink.href = '#';
  menuLink.textContent = menuLabel;
  loggedAs.parentNode.insertBefore(menuLink, loggedAs);

  // Create modal elements
  const overlay = document.createElement('div');
  overlay.className = 'ai-helper-stuff-todo-overlay';

  const modal = document.createElement('div');
  modal.className = 'ai-helper-stuff-todo-modal box';

  const header = document.createElement('div');
  header.className = 'ai-helper-stuff-todo-header';

  const titleEl = document.createElement('h3');
  titleEl.textContent = modalTitle;

  const closeBtn = document.createElement('button');
  closeBtn.className = 'ai-helper-stuff-todo-close';
  closeBtn.textContent = '\u00d7';
  closeBtn.setAttribute('aria-label', 'Close');

  header.appendChild(titleEl);
  header.appendChild(closeBtn);

  const body = document.createElement('div');
  body.className = 'ai-helper-stuff-todo-body';

  modal.appendChild(header);
  modal.appendChild(body);

  document.body.appendChild(overlay);
  document.body.appendChild(modal);

  let currentEventSource = null;

  // Open modal and start streaming
  function openModal() {
    overlay.style.display = 'block';
    modal.style.display = 'block';
    body.innerHTML = '<div class="ai-helper-loader"></div>';
    streamStuffTodo();
  }

  // Close modal and abort streaming
  function closeModal() {
    overlay.style.display = 'none';
    modal.style.display = 'none';
    if (currentEventSource) {
      currentEventSource.close();
      currentEventSource = null;
    }
  }

  // Stream stuff todo suggestions via SSE
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
      } catch (error) {
        // Silently handle parsing errors
      }
    };

    eventSource.onerror = function() {
      eventSource.close();
      currentEventSource = null;
      body.innerHTML = '<div class="ai-helper-error">' + errorText + '</div>';
    };
  }

  // Event handlers
  menuLink.addEventListener('click', function(e) {
    e.preventDefault();
    openModal();
  });

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
