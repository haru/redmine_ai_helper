class AiHelperTypoChecker {
  constructor(textarea, options = {}) {
    this.textarea = textarea;
    this.options = {
      contextType: options.contextType || 'general',
      endpoint: options.endpoint,
      debounceDelay: options.debounceDelay || 1000,
      minLength: options.minLength || 10,
      labels: options.labels || {}
    };
    
    this.suggestions = [];
    this.overlay = null;
    this.isEnabled = false;
    this.checkButton = null;
    this.currentDisplayedSuggestions = [];
  }

  init() {
    this.createOverlay();
    this.findExistingButton();
    this.attachEventListeners();
  }

  createOverlay() {
    // Create overlay element with same position and size as textarea (same as autocomplete)
    this.overlay = document.createElement('div');
    this.overlay.className = 'ai-helper-typo-overlay';

    // Copy styles from textarea (same as autocomplete)
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

    // Position overlay to match textarea exactly (same as autocomplete)
    this.overlay.style.position = 'absolute';
    this.overlay.style.pointerEvents = 'auto'; // Enable interactions for buttons
    this.overlay.style.zIndex = '15'; // Above textarea but below autocomplete
    this.overlay.style.overflowY = 'hidden';
    this.overlay.style.overflowX = 'hidden';
    this.overlay.style.whiteSpace = 'pre-wrap';
    this.overlay.style.wordWrap = 'break-word';

    // Function to update overlay position and size to match textarea (same as autocomplete)
    this.updateOverlayPosition = () => {
      const rect = this.textarea.getBoundingClientRect();
      const parentRect = this.textarea.parentNode.getBoundingClientRect();

      this.overlay.style.top = (rect.top - parentRect.top) + 'px';
      this.overlay.style.left = (rect.left - parentRect.left) + 'px';
      this.overlay.style.width = rect.width + 'px';
      this.overlay.style.height = rect.height + 'px';
    };

    // Ensure parent has relative positioning for overlay (same as autocomplete)
    const parent = this.textarea.parentNode;
    if (window.getComputedStyle(parent).position === 'static') {
      parent.style.position = 'relative';
    }

    // Insert overlay after textarea (same as autocomplete)
    parent.insertBefore(this.overlay, this.textarea.nextSibling);

    // Set initial position
    this.updateOverlayPosition();

    // Ensure textarea is above overlay and can receive input (same as autocomplete)
    this.textarea.style.position = 'relative';
    this.textarea.style.zIndex = '10'; // Higher z-index to ensure textarea is on top
    // Keep background transparent to show overlay suggestions
    this.textarea.style.backgroundColor = 'transparent';
  }

  findExistingButton() {
    // Map textarea IDs to button IDs
    const textareaToButtonMap = {
      'issue_description': 'ai-helper-typo-check-description-btn',
      'issue_notes': 'ai-helper-typo-check-notes-btn',
      'content_text': 'ai-helper-typo-check-wiki-btn'
    };
    
    const buttonId = textareaToButtonMap[this.textarea.id];
    if (buttonId) {
      this.checkButton = document.getElementById(buttonId);
    }
    
    if (!this.checkButton) {
      console.warn('Typo check button not found for textarea:', this.textarea.id);
    }
  }

  attachEventListeners() {
    if (this.checkButton) {
      this.checkButton.addEventListener('click', () => {
        this.checkTypos();
      });
    }

    // Hide overlay when user starts typing or clicks outside
    this.textarea.addEventListener('input', () => {
      if (this.overlay && this.overlay.style.display === 'block') {
        this.hideOverlay();
      }
    });

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && this.overlay && this.overlay.style.display === 'block') {
        this.hideOverlay();
      }
    });

    document.addEventListener('click', (e) => {
      if (this.overlay && this.overlay.style.display === 'block' && 
          !this.overlay.contains(e.target) && 
          e.target !== this.checkButton &&
          e.target !== this.textarea) {
        this.hideOverlay();
      }
    });

    // Disable autocomplete when typo overlay is active
    this.textarea.addEventListener('focus', () => {
      if (this.overlay && this.overlay.style.display === 'block') {
        this.disableAutocompletion();
      }
    });
  }

  disableAutocompletion() {
    // Disable autocomplete functionality when typo overlay is active
    if (window.aiHelperInstances) {
      const instances = window.aiHelperInstances;
      if (instances.autoCompletion) {
        instances.autoCompletion.clearSuggestion();
        instances.autoCompletion.isEnabled = false;
      }
      if (instances.wikiAutoCompletion) {
        instances.wikiAutoCompletion.clearSuggestion();
        instances.wikiAutoCompletion.isEnabled = false;
      }
      if (instances.notesAutoCompletion) {
        instances.notesAutoCompletion.clearSuggestion();
        instances.notesAutoCompletion.isEnabled = false;
      }
    }
  }

  enableAutocompletion() {
    // Re-enable autocomplete functionality when typo overlay is hidden
    if (window.aiHelperInstances) {
      const instances = window.aiHelperInstances;
      if (instances.autoCompletion && instances.autoCompletion.checkbox && instances.autoCompletion.checkbox.checked) {
        instances.autoCompletion.isEnabled = true;
      }
      if (instances.wikiAutoCompletion && instances.wikiAutoCompletion.checkbox && instances.wikiAutoCompletion.checkbox.checked) {
        instances.wikiAutoCompletion.isEnabled = true;
      }
      if (instances.notesAutoCompletion && instances.notesAutoCompletion.checkbox && instances.notesAutoCompletion.checkbox.checked) {
        instances.notesAutoCompletion.isEnabled = true;
      }
    }
  }

  async checkTypos() {
    const text = this.textarea.value;
    if (!text || text.length < this.options.minLength) {
      return;
    }

    this.checkButton.disabled = true;
    this.checkButton.textContent = this.options.labels.checking || 'Checking...';

    try {
      const response = await fetch(this.options.endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({
          text: text
        })
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const data = await response.json();
      this.suggestions = data.suggestions || [];
      this.displayTypoOverlay();
    } catch (error) {
      console.error('Typo check failed:', error);
      this.showErrorMessage();
    } finally {
      this.checkButton.disabled = false;
      this.checkButton.textContent = this.options.labels.checkButton || 'Check';
    }
  }

  displayTypoOverlay() {
    if (this.suggestions.length === 0) {
      this.showNoSuggestionsMessage();
      return;
    }

    // Disable autocomplete
    this.disableAutocompletion();

    // Update overlay position
    this.updateOverlayPosition();

    // Get textarea background color for overlay
    const bgColor = this.getTextareaBackgroundColor();
    this.overlay.style.backgroundColor = bgColor;

    // Hide textarea text and show overlay content with suggestions
    this.textarea.style.color = 'transparent';

    // Build overlay content with inline corrections
    this.buildOverlayContent();

    // Sync scroll position with textarea
    this.overlay.scrollTop = this.textarea.scrollTop;
    this.overlay.scrollLeft = this.textarea.scrollLeft;

    // Show overlay
    this.overlay.style.display = 'block';
  }

  buildOverlayContent() {
    const text = this.textarea.value;
    this.overlay.innerHTML = '';

    // Sort suggestions by position (reverse order for easier processing)
    const sortedSuggestions = [...this.suggestions].sort((a, b) => a.position - b.position);

    let currentPosition = 0;
    let overlayContent = document.createElement('div');
    overlayContent.style.position = 'relative';
    overlayContent.style.lineHeight = window.getComputedStyle(this.textarea).lineHeight;

    sortedSuggestions.forEach((suggestion, sortedIndex) => {
      // Find the original index in this.suggestions array
      const originalIndex = this.suggestions.findIndex(s => 
        s.position === suggestion.position && 
        s.original === suggestion.original &&
        s.corrected === suggestion.corrected
      );

      // Add text before the typo
      if (currentPosition < suggestion.position) {
        const beforeText = text.substring(currentPosition, suggestion.position);
        const beforeSpan = document.createElement('span');
        beforeSpan.textContent = beforeText;
        beforeSpan.style.color = '#000000';
        overlayContent.appendChild(beforeSpan);
      }

      // Add the typo with strikethrough
      const typoSpan = document.createElement('span');
      typoSpan.className = 'ai-helper-typo-original';
      typoSpan.textContent = suggestion.original;
      typoSpan.style.textDecoration = 'line-through';
      typoSpan.style.color = '#ff6b6b';
      typoSpan.style.backgroundColor = '#ffebee';
      overlayContent.appendChild(typoSpan);

      // Add the correction
      const correctionSpan = document.createElement('span');
      correctionSpan.className = 'ai-helper-typo-correction';
      correctionSpan.textContent = suggestion.corrected;
      correctionSpan.style.color = '#4caf50';
      correctionSpan.style.backgroundColor = '#e8f5e8';
      correctionSpan.style.fontWeight = 'bold';
      overlayContent.appendChild(correctionSpan);

      // Add accept/reject buttons
      const buttonsContainer = document.createElement('span');
      buttonsContainer.className = 'ai-helper-typo-buttons';
      buttonsContainer.style.display = 'inline-block';
      buttonsContainer.style.marginLeft = '4px';
      buttonsContainer.style.verticalAlign = 'middle';

      const acceptBtn = document.createElement('button');
      acceptBtn.className = 'ai-helper-typo-accept-btn';
      acceptBtn.innerHTML = '✓';
      acceptBtn.title = this.options.labels.acceptSuggestion || 'Accept';
      acceptBtn.style.cssText = `
        background: #4caf50;
        color: white;
        border: none;
        border-radius: 3px;
        width: 20px;
        height: 20px;
        font-size: 12px;
        margin-right: 2px;
        cursor: pointer;
        display: inline-block;
        vertical-align: middle;
      `;
      acceptBtn.addEventListener('click', () => this.acceptSuggestion(originalIndex));

      const rejectBtn = document.createElement('button');
      rejectBtn.className = 'ai-helper-typo-reject-btn';
      rejectBtn.innerHTML = '✗';
      rejectBtn.title = this.options.labels.dismissSuggestion || 'Reject';
      rejectBtn.style.cssText = `
        background: #f44336;
        color: white;
        border: none;
        border-radius: 3px;
        width: 20px;
        height: 20px;
        font-size: 12px;
        cursor: pointer;
        display: inline-block;
        vertical-align: middle;
      `;
      rejectBtn.addEventListener('click', () => this.rejectSuggestion(originalIndex));

      buttonsContainer.appendChild(acceptBtn);
      buttonsContainer.appendChild(rejectBtn);
      overlayContent.appendChild(buttonsContainer);

      currentPosition = suggestion.position + suggestion.length;
    });

    // Add remaining text after last suggestion
    if (currentPosition < text.length) {
      const remainingText = text.substring(currentPosition);
      const remainingSpan = document.createElement('span');
      remainingSpan.textContent = remainingText;
      remainingSpan.style.color = '#000000';
      overlayContent.appendChild(remainingSpan);
    }

    this.overlay.appendChild(overlayContent);
  }

  acceptSuggestion(index) {
    const suggestion = this.suggestions[index];
    if (!suggestion) return;

    const text = this.textarea.value;
    const newText = text.substring(0, suggestion.position) + 
                   suggestion.corrected + 
                   text.substring(suggestion.position + suggestion.original.length);
    
    this.textarea.value = newText;

    // Update positions of remaining suggestions
    this.updateSuggestionsAfterEdit(suggestion.position, suggestion.original.length, suggestion.corrected.length);
    
    // Remove this suggestion
    this.suggestions.splice(index, 1);

    if (this.suggestions.length === 0) {
      this.hideOverlay();
    } else {
      // Rebuild overlay with remaining suggestions
      this.buildOverlayContent();
    }

    // Trigger input event for any listeners
    this.textarea.dispatchEvent(new Event('input', { bubbles: true }));
  }

  rejectSuggestion(index) {
    // Simply remove the suggestion without applying it
    this.suggestions.splice(index, 1);

    if (this.suggestions.length === 0) {
      this.hideOverlay();
    } else {
      // Rebuild overlay with remaining suggestions
      this.buildOverlayContent();
    }
  }

  updateSuggestionsAfterEdit(editPosition, originalLength, newLength) {
    const lengthDiff = newLength - originalLength;
    
    this.suggestions.forEach(suggestion => {
      if (suggestion.position > editPosition) {
        suggestion.position += lengthDiff;
      }
    });
  }

  hideOverlay() {
    if (this.overlay) {
      this.overlay.style.display = 'none';
      this.overlay.innerHTML = '';
      this.overlay.style.backgroundColor = 'transparent';
    }
    this.suggestions = [];
    this.textarea.style.color = '';
    
    // Re-enable autocomplete
    this.enableAutocompletion();
  }

  showNoSuggestionsMessage() {
    this.updateOverlayPosition();
    const bgColor = this.getTextareaBackgroundColor();
    this.overlay.style.backgroundColor = bgColor;
    
    this.overlay.innerHTML = `
      <div class="ai-helper-no-suggestions" style="
        position: absolute;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        background: white;
        padding: 20px;
        border: 1px solid #ddd;
        border-radius: 4px;
        text-align: center;
        box-shadow: 0 2px 8px rgba(0,0,0,0.1);
      ">
        <h4 style="margin: 0 0 10px 0; color: #333;">${this.options.labels.noSuggestions || 'No typos or errors found'}</h4>
        <p style="margin: 0; color: #666;">The text appears to be error-free.</p>
      </div>
    `;
    this.overlay.style.display = 'block';
    setTimeout(() => this.hideOverlay(), 3000);
  }

  showErrorMessage() {
    this.updateOverlayPosition();
    const bgColor = this.getTextareaBackgroundColor();
    this.overlay.style.backgroundColor = bgColor;
    
    this.overlay.innerHTML = `
      <div class="ai-helper-typo-error" style="
        position: absolute;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        background: white;
        padding: 20px;
        border: 1px solid #ddd;
        border-radius: 4px;
        text-align: center;
        box-shadow: 0 2px 8px rgba(0,0,0,0.1);
      ">
        <h4 style="margin: 0 0 10px 0; color: #f44336;">${this.options.labels.errorOccurred || 'An error occurred'}</h4>
        <p style="margin: 0; color: #666;">Please try again later.</p>
      </div>
    `;
    this.overlay.style.display = 'block';
    setTimeout(() => this.hideOverlay(), 3000);
  }

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

  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
  }
}

window.AiHelperTypoChecker = AiHelperTypoChecker;