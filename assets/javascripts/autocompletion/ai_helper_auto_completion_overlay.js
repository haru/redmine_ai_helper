// Suggestion overlay rendering and scroll handling for
// AiHelperAutoCompletion. Split out of ai_helper_auto_completion.js to keep
// that file under the max-lines ESLint limit (see ADR-027). A classic
// script can't split a single class body across files, so this file
// extends AiHelperAutoCompletion's static/prototype surface after the
// class is declared instead — same behavior as if these were defined
// inline in the class body. Must load after ai_helper_auto_completion.js
// (which declares `window.AiHelperAutoCompletion`).

AiHelperAutoCompletion.resolveBackgroundColor = function (element) {
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
};

Object.assign(AiHelperAutoCompletion.prototype, {
  // Get textarea background color for masking
  getTextareaBackgroundColor() {
    return AiHelperAutoCompletion.resolveBackgroundColor(this.textarea);
  },

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
  },

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
  },

  // Sync overlay scroll with textarea scroll
  syncScroll() {
    if (this.overlay) {
      this.overlay.scrollTop = this.textarea.scrollTop;
      this.overlay.scrollLeft = this.textarea.scrollLeft;
    }
  },

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
  },

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
  },

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
  },

  // Remove event listeners for scrollable overlay mode
  removeScrollableEventListeners() {
    if (!this.overlay || !this.scrollableClickHandler) {return;}

    this.overlay.removeEventListener('click', this.scrollableClickHandler);
    this.overlay.removeEventListener('keydown', this.scrollableKeydownHandler);
    this.scrollableClickHandler = null;
    this.scrollableKeydownHandler = null;
  },
});
