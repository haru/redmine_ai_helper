// AI Helper Auto Completion for Redmine Textarea Fields
// Provides GitHub Copilot-style inline completion for issue descriptions

class AiHelperAutoCompletion {
  constructor(textareaElement, options = {}) {
    this.textarea = textareaElement;
    this.overlay = null;
    this.currentSuggestion = null;
    this.debounceTimer = null;
    this.currentRequestId = 0; // Request ID management
    this.lastTextSnapshot = '';
    this.lastCursorPosition = 0;
    this.checkbox = null; // ON/OFF checkbox
    this.storageKey = 'aiHelperAutoCompletion';
    this.isEnabled = true;
    this.options = {
      debounceDelay: 500,
      minLength: 5,
      suggestionColor: '#888888',
      contextType: 'description',
      endpoint: '',
      labels: {
        toggleLabel: 'AI Completion',
        loading: 'Generating AI suggestions...',
        noSuggestions: 'No suggestions available',
        acceptSuggestion: 'Accept suggestion',
        dismiss: 'Dismiss',
        enabledTooltip: 'AI auto-completion is enabled. Press Tab to accept suggestions or Esc to dismiss.',
        disabledTooltip: 'AI auto-completion is disabled. Check the box to enable.'
      },
      ...options
    };
  }

  init() {
    this.createCheckbox();
    this.createOverlay();
    this.attachEventListeners();
    this.loadSettings();
  }

  createCheckbox() {
    // This method now expects the checkbox to be already created in ERB
    // Just find and reference the existing checkbox
    if (this.options.contextType === 'note') {
      this.checkbox = document.getElementById('ai-helper-autocompletion-notes-toggle');
      this.container = document.getElementById('ai-helper-notes-checkbox-container');
    } else if (this.options.contextType === 'wiki') {
      this.checkbox = document.getElementById('ai-helper-autocompletion-wiki-toggle');
      this.container = document.getElementById('ai-helper-wiki-checkbox-container');
    } else {
      this.checkbox = document.getElementById('ai-helper-autocompletion-description-toggle');
      this.container = document.getElementById('ai-helper-description-checkbox-container');
    }
    
    if (this.checkbox) {
      this.checkbox.addEventListener('change', () => {
        this.saveSettings();
        if (!this.checkbox.checked) {
          this.clearSuggestion();
        }
      });
    }
  }

  createOverlay() {
    // Create overlay element with same position and size as textarea
    this.overlay = document.createElement('div');
    this.overlay.className = 'ai-helper-textarea-overlay';
    
    // Copy styles from textarea
    const computedStyle = window.getComputedStyle(this.textarea);
    this.overlay.style.font = computedStyle.font;
    this.overlay.style.fontSize = computedStyle.fontSize;
    this.overlay.style.fontFamily = computedStyle.fontFamily;
    this.overlay.style.lineHeight = computedStyle.lineHeight;
    
    // Copy padding but add extra right padding to prevent text overflow
    const paddingTop = computedStyle.paddingTop;
    const paddingRight = computedStyle.paddingRight;
    const paddingBottom = computedStyle.paddingBottom;
    const paddingLeft = computedStyle.paddingLeft;
    
    // Copy padding normally since width is adjusted instead
    this.overlay.style.paddingTop = paddingTop;
    this.overlay.style.paddingRight = paddingRight;
    this.overlay.style.paddingBottom = paddingBottom;
    this.overlay.style.paddingLeft = paddingLeft;
    
    this.overlay.style.border = computedStyle.border;
    this.overlay.style.borderColor = 'transparent';
    this.overlay.style.backgroundColor = 'transparent';
    this.overlay.style.boxSizing = 'border-box'; // Ensure consistent sizing with textarea
    
    // Position overlay to match textarea exactly
    this.overlay.style.position = 'absolute';
    this.overlay.style.pointerEvents = 'none';
    this.overlay.style.zIndex = '5'; // Below textarea but above background
    this.overlay.style.overflow = 'hidden';
    this.overlay.style.whiteSpace = 'pre-wrap';
    this.overlay.style.wordWrap = 'break-word';
    
    // Function to update overlay position and size to match textarea
    this.updateOverlayPosition = () => {
      const rect = this.textarea.getBoundingClientRect();
      const parentRect = this.textarea.parentNode.getBoundingClientRect();
      
      this.overlay.style.top = (rect.top - parentRect.top) + 'px';
      this.overlay.style.left = (rect.left - parentRect.left) + 'px';
      this.overlay.style.width = rect.width + 'px';
      this.overlay.style.height = rect.height + 'px';
    };
    
    // Ensure parent has relative positioning for overlay
    const parent = this.textarea.parentNode;
    if (window.getComputedStyle(parent).position === 'static') {
      parent.style.position = 'relative';
    }
    
    // Insert overlay after textarea
    parent.insertBefore(this.overlay, this.textarea.nextSibling);
    
    // Set initial position
    this.updateOverlayPosition();
    
    // Ensure textarea is above overlay and can receive input
    this.textarea.style.position = 'relative';
    this.textarea.style.zIndex = '10'; // Higher z-index to ensure textarea is on top
    // Keep background transparent to show overlay suggestions
    this.textarea.style.backgroundColor = 'transparent';
  }

  attachEventListeners() {
    // Text change events
    this.textarea.addEventListener('input', () => this.onTextChange());
    this.textarea.addEventListener('keyup', () => this.onTextChange());
    this.textarea.addEventListener('click', () => this.onTextChange());
    this.textarea.addEventListener('keydown', (e) => this.onKeyDown(e));
    
    // Focus events
    this.textarea.addEventListener('focus', () => this.onFocus());
    this.textarea.addEventListener('blur', () => this.onBlur());
    
    // Manual trigger shortcut
    this.textarea.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.code === 'Space') {
        e.preventDefault();
        this.requestSuggestion();
      }
    });
  }

  loadSettings() {
    const saved = localStorage.getItem(this.storageKey);
    const enabled = saved ? JSON.parse(saved).enabled : true; // Default ON
    if (this.checkbox) {
      this.checkbox.checked = enabled;
    }
    this.isEnabled = enabled;
  }

  saveSettings() {
    if (this.checkbox) {
      const settings = { enabled: this.checkbox.checked };
      this.isEnabled = this.checkbox.checked;
      localStorage.setItem(this.storageKey, JSON.stringify(settings));
    }
  }

  onTextChange() {
    // Clear existing suggestion immediately when input changes
    this.clearSuggestion();
    
    // Cancel pending request
    this.cancelPendingRequest();
    
    // Start new debounce
    this.scheduleCompletion();
  }

  onKeyDown(e) {
    if (this.currentSuggestion) {
      if (e.key === 'Tab') {
        e.preventDefault();
        this.acceptSuggestion();
        return false;
      } else if (e.key === 'Escape') {
        e.preventDefault();
        this.clearSuggestion();
        return false;
      }
    }
  }

  onFocus() {
    // Show overlay when focused
    if (this.overlay) {
      this.overlay.style.display = 'block';
    }
  }

  onBlur() {
    // Hide overlay when focus is lost (with small delay)
    setTimeout(() => {
      if (this.overlay) {
        this.overlay.style.display = 'none';
      }
      this.clearSuggestion();
    }, 100);
  }

  scheduleCompletion() {
    // Skip processing if autocompletion is disabled
    if (!this.isEnabled) {
      return;
    }

    const text = this.textarea.value;
    const cursorPosition = this.textarea.selectionStart;

    // Check minimum length requirement
    if (text.length < this.options.minLength) {
      return;
    }

    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      this.requestSuggestion();
    }, this.options.debounceDelay);
  }

  requestSuggestion() {
    const text = this.textarea.value;
    const cursorPosition = this.textarea.selectionStart;
    
    // Save snapshot
    this.lastTextSnapshot = text;
    this.lastCursorPosition = cursorPosition;
    
    // Generate new request ID
    const requestId = ++this.currentRequestId;
    
    // API call
    this.callCompletionAPI(text, cursorPosition, requestId);
  }

  callCompletionAPI(text, cursorPosition, requestId) {
    // Get CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    
    const headers = { 
      'Content-Type': 'application/json',
      'X-Requested-With': 'XMLHttpRequest'
    };
    
    if (csrfToken) {
      headers['X-CSRF-Token'] = csrfToken;
    }
    
    // Get project ID for new issues
    const requestBody = {
      text: text,
      cursor_position: cursorPosition
    };
    
    // For new issues, try to get project_id from form or URL
    if (this.options.endpoint.includes('/new/')) {
      const projectSelect = document.querySelector('#issue_project_id');
      const projectId = projectSelect ? projectSelect.value : null;
      if (projectId) {
        requestBody.project_id = projectId;
      } else {
        // Try to get from URL
        const urlMatch = window.location.pathname.match(/\/projects\/([^\/]+)/);
        if (urlMatch) {
          requestBody.project_identifier = urlMatch[1];
        }
      }
    }
    
    fetch(this.options.endpoint, {
      method: 'POST',
      headers: headers,
      body: JSON.stringify(requestBody)
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      return response.json();
    })
    .then(data => {
      // Check for race condition when receiving response
      if (this.isRequestStale(requestId, text, cursorPosition)) {
        return;
      }
      
      if (data.suggestion && data.suggestion.trim()) {
        this.displayInlineSuggestion(data.suggestion, cursorPosition);
      }
    })
    .catch(error => {
      if (this.currentRequestId === requestId) {
        console.error('Completion error:', error);
      }
    });
  }

  isRequestStale(requestId, originalText, originalCursor) {
    // Request ID is stale
    if (requestId !== this.currentRequestId) {
      return true;
    }
    
    // Text or cursor position has changed
    const currentText = this.textarea.value;
    const currentCursor = this.textarea.selectionStart;
    
    return (originalText !== currentText || originalCursor !== currentCursor);
  }

  cancelPendingRequest() {
    // Invalidate existing request by advancing request ID
    this.currentRequestId++;
  }

  // Get textarea background color for masking
  getTextareaBackgroundColor() {
    const computedStyle = window.getComputedStyle(this.textarea);
    let bgColor = computedStyle.backgroundColor;
    
    // If transparent or rgba(0,0,0,0), use parent background or default to white
    if (bgColor === 'transparent' || bgColor === 'rgba(0, 0, 0, 0)') {
      const parent = this.textarea.parentNode;
      const parentStyle = window.getComputedStyle(parent);
      bgColor = parentStyle.backgroundColor;
      
      // If still transparent, default to white
      if (bgColor === 'transparent' || bgColor === 'rgba(0, 0, 0, 0)') {
        bgColor = '#ffffff';
      }
    }
    
    return bgColor;
  }


  displayInlineSuggestion(suggestion, cursorPosition) {
    const text = this.textarea.value;
    const beforeCursor = text.substring(0, cursorPosition);
    const afterCursor = text.substring(cursorPosition);
    
    // Store current suggestion
    this.currentSuggestion = {
      text: suggestion,
      cursorPosition: cursorPosition
    };
    
    // Update overlay position to match textarea exactly
    this.updateOverlayPosition();
    
    // Hide textarea temporarily and show overlay with full content
    this.textarea.style.color = 'transparent';
    
    // Set background color for overlay to match textarea
    const bgColor = this.getTextareaBackgroundColor();
    this.overlay.style.backgroundColor = bgColor;
    
    // Create overlay content with suggestion
    const suggestionSpan = document.createElement('span');
    suggestionSpan.className = 'ai-helper-inline-suggestion ai-helper-suggestion-active';
    suggestionSpan.textContent = suggestion;
    suggestionSpan.style.color = this.options.suggestionColor;
    
    // Add click handler to suggestion
    suggestionSpan.addEventListener('click', () => {
      this.acceptSuggestion();
    });
    
    // Update overlay content - show full text with highlighted suggestion
    this.overlay.innerHTML = '';
    
    // Create spans for all text parts to control colors
    const beforeSpan = document.createElement('span');
    beforeSpan.textContent = beforeCursor;
    beforeSpan.style.color = '#000000'; // Normal text color
    
    const afterSpan = document.createElement('span');
    afterSpan.textContent = afterCursor;
    afterSpan.style.color = '#000000'; // Normal text color
    
    this.overlay.appendChild(beforeSpan);
    this.overlay.appendChild(suggestionSpan);
    this.overlay.appendChild(afterSpan);
    
    // Sync scroll position with textarea
    this.overlay.scrollTop = this.textarea.scrollTop;
    this.overlay.scrollLeft = this.textarea.scrollLeft;
    
    // Make sure overlay is visible
    this.overlay.style.display = 'block';
  }

  acceptSuggestion() {
    if (!this.currentSuggestion) {
      return;
    }
    
    const text = this.textarea.value;
    const cursorPos = this.currentSuggestion.cursorPosition;
    const suggestion = this.currentSuggestion.text;
    
    // Insert suggestion at cursor position
    const newText = text.substring(0, cursorPos) + suggestion + text.substring(cursorPos);
    this.textarea.value = newText;
    
    // Move cursor to end of inserted suggestion
    const newCursorPos = cursorPos + suggestion.length;
    this.textarea.setSelectionRange(newCursorPos, newCursorPos);
    
    // Clear suggestion
    this.clearSuggestion();
    
    // Trigger input event for any listeners
    this.textarea.dispatchEvent(new Event('input', { bubbles: true }));
    
    // Focus back on textarea
    this.textarea.focus();
  }

  clearSuggestion() {
    // Clear displayed suggestion
    this.currentSuggestion = null;
    if (this.overlay) {
      this.overlay.innerHTML = '';
      this.overlay.style.backgroundColor = 'transparent';
    }
    // Restore textarea text visibility
    this.textarea.style.color = '';
  }

  // Sync overlay scroll with textarea scroll
  syncScroll() {
    if (this.overlay) {
      this.overlay.scrollTop = this.textarea.scrollTop;
      this.overlay.scrollLeft = this.textarea.scrollLeft;
    }
  }

  // Cleanup method
  destroy() {
    // Remove event listeners
    this.textarea.removeEventListener('input', this.onTextChange);
    this.textarea.removeEventListener('keyup', this.onTextChange);
    this.textarea.removeEventListener('click', this.onTextChange);
    this.textarea.removeEventListener('keydown', this.onKeyDown);
    this.textarea.removeEventListener('focus', this.onFocus);
    this.textarea.removeEventListener('blur', this.onBlur);
    
    // Clear timers
    clearTimeout(this.debounceTimer);
    
    // Remove DOM elements
    if (this.overlay) {
      this.overlay.remove();
    }
    if (this.checkbox && this.checkbox.parentNode) {
      this.checkbox.parentNode.remove();
    }
    
    // Reset textarea styles
    this.textarea.style.backgroundColor = '';
    this.textarea.style.position = '';
    this.textarea.style.zIndex = '';
  }
}

// Auto-completion class for AI Helper
// Initialization is handled by view partials