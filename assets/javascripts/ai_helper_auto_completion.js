// AI Helper Auto Completion for Redmine Textarea Fields
// Provides GitHub Copilot-style inline completion for issue descriptions

class AiHelperAutoCompletion {
  constructor(textareaElement, options = {}) {
    this.textarea = textareaElement;
    this.overlay = null;
    this.currentSuggestion = null;
    this.debounceTimer = null;
    this.currentRequestId = 0; // Request ID management
    this.abortController = null; // Aborts the in-flight completion request
    this.lastTextSnapshot = null;
    this.lastCursorPosition = null;
    this.checkbox = null; // ON/OFF checkbox
    this.userId = options.userId || 'anonymous';
    this.storageKey = `aiHelperAutoCompletion_${this.userId}`;
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
    this.overlay.style.overflowY = 'hidden';
    this.overlay.style.overflowX = 'hidden';
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
    // Kept on the instance so destroy() can pass the identical references to
    // removeEventListener: a fresh wrapper would silently remove nothing.
    this.boundOnTextChange = () => this.onTextChange();
    this.boundOnKeyDown = (e) => this.onKeyDown(e);
    this.boundOnFocus = () => this.onFocus();
    this.boundOnBlur = () => this.onBlur();
    this.boundOnManualTrigger = (e) => {
      if ((e.ctrlKey || e.metaKey) && e.code === 'Space') {
        e.preventDefault();
        this.requestSuggestion();
      }
    };

    // Text change events
    this.textarea.addEventListener('input', this.boundOnTextChange);
    this.textarea.addEventListener('keyup', this.boundOnTextChange);
    this.textarea.addEventListener('click', this.boundOnTextChange);
    this.textarea.addEventListener('keydown', this.boundOnKeyDown);

    // Focus events
    this.textarea.addEventListener('focus', this.boundOnFocus);
    this.textarea.addEventListener('blur', this.boundOnBlur);

    // Manual trigger shortcut
    this.textarea.addEventListener('keydown', this.boundOnManualTrigger);
  }

  loadSettings() {
    const saved = localStorage.getItem(this.storageKey);
    const enabled = saved ? JSON.parse(saved).enabled : false; // Default OFF
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
    // keyup and click fire for things that change nothing — a modifier key
    // released, a click landing on the caret. The displayed suggestion still
    // answers this exact state, so it stays, and there is nothing to request.
    if (this.textarea.value === this.lastTextSnapshot &&
        this.textarea.selectionStart === this.lastCursorPosition) {
      return;
    }

    // Clear existing suggestion immediately when input changes. This also
    // cancels the in-flight and the scheduled request, so no separate cancel
    // call is needed here.
    this.clearSuggestion();

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
    // Drop any completion scheduled earlier: either it is superseded by this
    // call, or the conditions below no longer allow it to run
    clearTimeout(this.debounceTimer);

    // Skip processing if autocompletion is disabled
    if (!this.isEnabled) {
      return;
    }

    const text = this.textarea.value;

    // Check minimum length requirement
    if (text.length < this.options.minLength) {
      return;
    }

    this.debounceTimer = setTimeout(() => {
      this.requestSuggestion();
    }, this.options.debounceDelay);
  }

  requestSuggestion() {
    const text = this.textarea.value;
    const cursorPosition = this.textarea.selectionStart;

    // Nothing changed since the last request that produced an answer, so the
    // answer would be the same. The snapshot is dropped again the moment that
    // answer stops being in hand — aborted, failed, empty, or taken off screen —
    // so only a state whose answer the user still has suppresses a request here.
    // See docs/adr/019-completion-request-suppression-tied-to-displayed-suggestion.md
    // and docs/adr/021-snapshot-teardown-belongs-to-clear-suggestion.md.
    if (text === this.lastTextSnapshot && cursorPosition === this.lastCursorPosition) {
      return;
    }

    this.lastTextSnapshot = text;
    this.lastCursorPosition = cursorPosition;

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
    let requestBody;

    // Use customRequestData function if provided
    if (this.options.customRequestData && typeof this.options.customRequestData === 'function') {
      requestBody = this.options.customRequestData(text, cursorPosition);
    } else {
      requestBody = {
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
          const urlMatch = window.location.pathname.match(/\/projects\/([^/]+)/);
          if (urlMatch) {
            requestBody.project_identifier = urlMatch[1];
          }
        }
      }
    }

    // Abort the previous in-flight request so that at most one completion
    // request per instance is ever open
    if (this.abortController) {
      this.abortController.abort();
    }
    const controller = new AbortController();
    this.abortController = controller;

    fetch(this.options.endpoint, {
      method: 'POST',
      headers: headers,
      body: JSON.stringify(requestBody),
      signal: controller.signal
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      return response.json();
    })
    .then(data => {
      this.releaseAbortController(controller);

      // Check for race condition when receiving response
      if (this.isRequestStale(requestId, text, cursorPosition)) {
        this.forgetRequestSnapshot(text, cursorPosition);
        return;
      }

      if (data.suggestion && data.suggestion.trim()) {
        this.displayInlineSuggestion(data.suggestion, cursorPosition);
        return;
      }

      // The server answered with nothing to show — no candidate, or a timeout,
      // which returns 200 with an empty suggestion by design (ADR-018). With no
      // suggestion on screen the snapshot has nothing to stand for, so keeping
      // it would lock completion at this position until the text changes.
      this.forgetRequestSnapshot(text, cursorPosition);
    })
    .catch(error => {
      this.releaseAbortController(controller);

      // This text/cursor pair never got an answer, so it must not stay recorded
      // as already requested. Without this, aborting (blur, Esc, accept) or a
      // failing request would suppress every later attempt at the same position
      // until the user edits the text again.
      this.forgetRequestSnapshot(text, cursorPosition);

      // Aborting a superseded request is expected, not a failure
      if (error.name === 'AbortError') {
        return;
      }

      // Logged unconditionally: clearSuggestion advances the request ID on
      // every keystroke, click and blur, so gating the log on it would hide
      // genuine server errors behind an ordinary click in the textarea.
      console.error('Completion error:', error);
    });
  }

  // Forget the given controller when it is still the current one, so that
  // a non-null abortController always means a request is in flight
  releaseAbortController(controller) {
    if (this.abortController === controller) {
      this.abortController = null;
    }
  }

  // Drop the recorded snapshot when it still describes the given request, so a
  // newer request that has already overwritten it is left alone. null is used
  // rather than '' / 0 so the snapshot can never match a real textarea state.
  forgetRequestSnapshot(text, cursorPosition) {
    if (this.lastTextSnapshot === text && this.lastCursorPosition === cursorPosition) {
      this.lastTextSnapshot = null;
      this.lastCursorPosition = null;
    }
  }

  static isRequestStale(requestId, currentRequestId, originalText, currentText, originalCursor, currentCursor) {
    if (requestId !== currentRequestId) {
      return true;
    }
    return (originalText !== currentText || originalCursor !== currentCursor);
  }

  isRequestStale(requestId, originalText, originalCursor) {
    return AiHelperAutoCompletion.isRequestStale(
      requestId, this.currentRequestId, originalText,
      this.textarea.value, originalCursor, this.textarea.selectionStart
    );
  }

  cancelPendingRequest() {
    // Drop the completion that is merely scheduled. Nothing reschedules it on
    // the disable, blur and destroy paths, so without this a request still
    // fires after the user has turned completion off or left the field.
    clearTimeout(this.debounceTimer);

    // Invalidate existing request by advancing request ID
    this.currentRequestId++;

    // Abort the in-flight request at the network level so the connection is
    // released immediately instead of only being ignored on arrival
    if (this.abortController) {
      this.abortController.abort();
      this.abortController = null;
    }
  }

  static resolveBackgroundColor(element) {
    const computedStyle = window.getComputedStyle(element);
    let bgColor = computedStyle.backgroundColor;

    if (bgColor === 'transparent' || bgColor === 'rgba(0, 0, 0, 0)') {
      const parent = element.parentNode;
      const parentStyle = window.getComputedStyle(parent);
      bgColor = parentStyle.backgroundColor;

      if (bgColor === 'transparent' || bgColor === 'rgba(0, 0, 0, 0)') {
        bgColor = '#ffffff';
      }
    }

    return bgColor;
  }

  // Get textarea background color for masking
  getTextareaBackgroundColor() {
    return AiHelperAutoCompletion.resolveBackgroundColor(this.textarea);
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
    
    // Check if scrolling is needed for long content (delay to ensure DOM is rendered)
    setTimeout(() => {
      this.checkAndEnableScrolling();
    }, 0);
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

    // Accepting inserted text, so the textarea no longer matches the snapshot:
    // the input event dispatched below reaches the debounce and fetches the
    // follow-on suggestion, the way accepting one completion leads into the next.
    this.clearSuggestion();

    // Trigger input event for any listeners
    this.textarea.dispatchEvent(new Event('input', { bubbles: true }));

    // Focus back on textarea
    this.textarea.focus();
  }

  clearSuggestion() {
    // A snapshot only earns its suppression while the answer it stands for is
    // on screen, so taking a suggestion off screen takes the snapshot with it —
    // whichever path got us here. Keeping it would block every later request at
    // this exact text/cursor, leaving the user with no suggestion and no way to
    // ask for one. Accepting is unaffected: it rewrites the textarea first, so
    // the guard inside forgetRequestSnapshot leaves the old snapshot alone.
    // See docs/adr/019-completion-request-suppression-tied-to-displayed-suggestion.md.
    if (this.currentSuggestion) {
      this.forgetRequestSnapshot(this.textarea.value, this.textarea.selectionStart);
    }

    // Every teardown path (disabling, blur, accept, Esc, new input) goes through
    // here, so cancelling the in-flight and the scheduled request in one place
    // covers all of them; destroy() cancels separately because it tears the
    // instance down without clearing the UI.
    this.cancelPendingRequest();

    // Clear displayed suggestion
    this.currentSuggestion = null;
    if (this.overlay) {
      this.overlay.innerHTML = '';
      this.overlay.style.backgroundColor = 'transparent';
      // Reset scrolling settings
      this.resetScrolling();
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

  // Check if scrolling is needed and enable it when content exceeds height
  checkAndEnableScrolling() {
    if (!this.overlay) {return;}
    
    const contentHeight = this.overlay.scrollHeight;
    const overlayHeight = this.overlay.clientHeight;
    
    if (contentHeight > overlayHeight) {
      // Content exceeds height, enable scrolling
      this.overlay.style.overflowY = 'auto';
      this.overlay.style.overflowX = 'hidden';
      
      // Enable pointer events to allow scrolling interaction
      this.overlay.style.pointerEvents = 'auto';
      
      // Move overlay above textarea to capture mouse events
      this.overlay.style.zIndex = '10';
      
      // Show textarea border on overlay since it's now on top
      const computedStyle = window.getComputedStyle(this.textarea);
      this.overlay.style.borderColor = computedStyle.borderColor;
      
      // Add scrollable class for visual styling
      this.overlay.classList.add('ai-helper-scrollable-overlay');
      
      // Add event listeners to forward events to textarea when needed
      this.addScrollableEventListeners();
    } else {
      // Content fits within height, use default behavior
      this.overlay.style.overflowY = 'hidden';
      this.overlay.style.overflowX = 'hidden';
      
      // Restore original pointer events and z-index settings
      this.overlay.style.pointerEvents = 'none';
      this.overlay.style.zIndex = '5';
      this.overlay.style.borderColor = 'transparent';
      this.overlay.classList.remove('ai-helper-scrollable-overlay');
      
      // Remove scrollable event listeners
      this.removeScrollableEventListeners();
    }
  }

  // Reset scrolling settings to default state
  resetScrolling() {
    if (!this.overlay) {return;}
    
    this.overlay.style.overflowY = 'hidden';
    this.overlay.style.overflowX = 'hidden';
    this.overlay.style.pointerEvents = 'none';
    this.overlay.style.zIndex = '5';
    this.overlay.style.borderColor = 'transparent';
    this.overlay.classList.remove('ai-helper-scrollable-overlay');
    this.removeScrollableEventListeners();
  }

  // Add event listeners for scrollable overlay mode
  addScrollableEventListeners() {
    if (!this.overlay) {return;}
    
    // Store bound functions for later removal
    this.scrollableClickHandler = (e) => {
      // Only forward click if not on suggestion text
      if (!e.target.classList.contains('ai-helper-inline-suggestion')) {
        this.textarea.focus();
      }
    };
    
    this.scrollableKeydownHandler = (e) => {
      // Forward keyboard events to textarea except for scroll keys
      if (!['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End'].includes(e.key)) {
        this.textarea.dispatchEvent(new KeyboardEvent(e.type, e));
        this.textarea.focus();
      }
    };
    
    this.overlay.addEventListener('click', this.scrollableClickHandler);
    this.overlay.addEventListener('keydown', this.scrollableKeydownHandler);
  }

  // Remove event listeners for scrollable overlay mode
  removeScrollableEventListeners() {
    if (!this.overlay || !this.scrollableClickHandler) {return;}
    
    this.overlay.removeEventListener('click', this.scrollableClickHandler);
    this.overlay.removeEventListener('keydown', this.scrollableKeydownHandler);
    this.scrollableClickHandler = null;
    this.scrollableKeydownHandler = null;
  }

  // Cleanup method
  destroy() {
    // Remove event listeners, using the same references attachEventListeners
    // registered — removeEventListener silently ignores anything else
    this.textarea.removeEventListener('input', this.boundOnTextChange);
    this.textarea.removeEventListener('keyup', this.boundOnTextChange);
    this.textarea.removeEventListener('click', this.boundOnTextChange);
    this.textarea.removeEventListener('keydown', this.boundOnKeyDown);
    this.textarea.removeEventListener('focus', this.boundOnFocus);
    this.textarea.removeEventListener('blur', this.boundOnBlur);
    this.textarea.removeEventListener('keydown', this.boundOnManualTrigger);

    // Abort the in-flight request and drop the scheduled one, so navigating
    // away leaves nothing pending
    this.cancelPendingRequest();

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
window.AiHelperAutoCompletion = AiHelperAutoCompletion;
