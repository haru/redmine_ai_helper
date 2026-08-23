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
    this.isProcessingSuggestion = false;
    this.isOverlayVisible = false;
    this.isCheckingTypos = false;
  }

  init() {
    this.createOverlay();
    this.findControlPanel();
    this.findExistingButton();
    this.attachEventListeners();
  }

  findControlPanel() {
    // Map textarea IDs to control panel IDs
    const textareaToControlPanelMap = {
      'issue_description': 'ai-helper-typo-control-panel-description',
      'issue_notes': 'ai-helper-typo-control-panel-notes', 
      'content_text': 'ai-helper-typo-control-panel-wiki'
    };
    
    const panelId = textareaToControlPanelMap[this.textarea.id];
    if (panelId) {
      this.controlPanel = document.getElementById(panelId);
    }
    
    if (!this.controlPanel) {
      return;
    }

    // Position panel at bottom-right of textarea
    const parent = this.textarea.parentNode;
    if (window.getComputedStyle(parent).position === 'static') {
      parent.classList.add('ai-helper-textarea-parent-relative');
    }
    
    // Move control panel to textarea's parent if not already there
    if (this.controlPanel.parentNode !== parent) {
      parent.appendChild(this.controlPanel);
    }
    
    // Find buttons and attach event listeners
    this.applyAllButton = this.controlPanel.querySelector('.ai-helper-typo-apply-all-btn');
    this.closeButton = this.controlPanel.querySelector('.ai-helper-typo-close-btn');
    
    if (this.applyAllButton) {
      this.applyAllButton.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        this.acceptAllSuggestions();
      });
    }
    
    if (this.closeButton) {
      this.closeButton.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        this.hideOverlay();
      });
    }
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
    this.overlay.style.overflowWrap = 'break-word';

    // Function to update overlay position and size to match textarea (same as autocomplete)
    this.updateOverlayPosition = () => {
      const rect = this.textarea.getBoundingClientRect();
      const parentRect = this.textarea.parentNode.getBoundingClientRect();

      this.overlay.style.top = (rect.top - parentRect.top) + 'px';
      this.overlay.style.left = (rect.left - parentRect.left) + 'px';
      this.overlay.style.width = rect.width + 'px';
      this.overlay.style.height = rect.height + 'px';
    };

    // Function to update control panel position
    this.updateControlPanelPosition = () => {
      if (!this.controlPanel) {return;}
      
      const rect = this.textarea.getBoundingClientRect();
      const parentRect = this.textarea.parentNode.getBoundingClientRect();

      // Position at bottom-right of textarea
      this.controlPanel.style.position = 'absolute';
      this.controlPanel.style.top = (rect.bottom - parentRect.top - 40) + 'px'; // 40px from bottom
      this.controlPanel.style.right = '10px'; // 10px from right edge of parent
      this.controlPanel.style.zIndex = '25'; // Above overlay
    };

    // Ensure parent has relative positioning for overlay (same as autocomplete)
    const parent = this.textarea.parentNode;
    if (window.getComputedStyle(parent).position === 'static') {
      parent.classList.add('ai-helper-textarea-parent-relative');
    }

    // Insert overlay after textarea (same as autocomplete)
    parent.insertBefore(this.overlay, this.textarea.nextSibling);

    // Set initial position
    this.updateOverlayPosition();

    // Ensure textarea is above overlay and can receive input (same as autocomplete)
    this.textarea.classList.add('ai-helper-textarea-positioned');
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
  }

  attachEventListeners() {
    if (this.checkButton) {
      // Remove any existing event listeners to prevent duplicates
      this.checkButton.removeEventListener('click', this.checkTyposHandler);
      
      // Create bound handler for later removal
      this.checkTyposHandler = () => {
        this.checkTypos();
      };
      
      this.checkButton.addEventListener('click', this.checkTyposHandler);
    }

    // Hide overlay when user starts typing or clicks outside
    this.textarea.addEventListener('input', () => {
      if (this.isProcessingSuggestion) {
        return;
      }
      if (this.overlay && this.isOverlayActive()) {
        this.hideOverlay();
      }
    });

    document.addEventListener('keydown', (e) => {
      if (this.isProcessingSuggestion) {
        return;
      }
      if (e.key === 'Escape' && this.overlay && this.isOverlayActive()) {
        this.hideOverlay();
      }
    });

    document.addEventListener('click', (e) => {
      if (this.isProcessingSuggestion) {
        return;
      }
      if (this.overlay && this.isOverlayActive() && 
          !this.overlay.contains(e.target) && 
          e.target !== this.checkButton &&
          e.target !== this.textarea) {
        this.hideOverlay();
      }
    });

    // Disable autocomplete when typo overlay is active
    this.textarea.addEventListener('focus', () => {
      if (this.overlay && this.isOverlayActive()) {
        this.disableAutocompletion();
      }
    });

    // Sync overlay scroll with textarea scroll
    this.textarea.addEventListener('scroll', () => {
      this.syncScroll();
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
    // Prevent duplicate execution
    if (this.isCheckingTypos) {
      return;
    }
    
    const text = this.textarea.value;
    
    if (!text || text.length < this.options.minLength) {
      return;
    }

    this.isCheckingTypos = true;
    this.checkButton.disabled = true;
    
    // Store original innerHTML to restore it later
    if (!this.originalButtonHTML) {
      this.originalButtonHTML = this.checkButton.innerHTML;
    }
    
    // Replace only the text part while keeping the icon
    const checkingText = this.options.labels.checking || 'Checking...';
    const iconMatch = this.checkButton.innerHTML.match(/<svg[^>]*>.*?<\/svg>/);
    if (iconMatch) {
      this.checkButton.innerHTML = iconMatch[0] + ' ' + checkingText;
    } else {
      this.checkButton.textContent = checkingText;
    }

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
      this.isCheckingTypos = false;
      this.checkButton.disabled = false;
      
      // Restore original innerHTML instead of setting textContent
      if (this.originalButtonHTML) {
        this.checkButton.innerHTML = this.originalButtonHTML;
      } else {
        this.checkButton.textContent = this.options.labels.checkButton || 'Check';
      }
    }
  }

  // Overlay content rendering and suggestion accept/reject interactions
  // (displayTypoOverlay, buildOverlayContent, accept/reject*, hideOverlay,
  // showNoSuggestionsMessage, showErrorMessage, and their static helpers)
  // live in ai_helper_typo_suggestion_overlay.js — see the comment there.
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

  // Helper method to check if overlay is visible using CSS classes
  isOverlayActive() {
    return this.overlay && this.overlay.classList.contains('ai-helper-typo-overlay-active');
  }

  // Sync overlay scroll with textarea scroll
  syncScroll() {
    if (this.overlay && this.textarea) {
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
      this.overlay.classList.add('ai-helper-typo-overlay-scrollable');
      
      // Enable pointer events to allow scrolling interaction
      this.overlay.style.pointerEvents = 'auto';
      
      // Move overlay above textarea to capture mouse events
      this.overlay.style.zIndex = '20';
      
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
      this.overlay.style.pointerEvents = 'auto';
      this.overlay.style.zIndex = '15';
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
    this.overlay.style.pointerEvents = 'auto';
    this.overlay.style.zIndex = '15';
    this.overlay.style.borderColor = 'transparent';
    this.overlay.classList.remove('ai-helper-scrollable-overlay');
    this.removeScrollableEventListeners();
  }

  // Add event listeners for scrollable overlay mode
  addScrollableEventListeners() {
    if (!this.overlay) {return;}
    
    // Store bound functions for later removal
    this.scrollableClickHandler = (e) => {
      // Allow clicks on typo correction buttons
      if (e.target.classList.contains('ai-helper-typo-accept-btn') || 
          e.target.classList.contains('ai-helper-typo-reject-btn')) {
        return; // Let the button click handlers work normally
      }
      
      // Forward other clicks to textarea
      if (!e.target.closest('.ai-helper-typo-buttons')) {
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

}

window.AiHelperTypoChecker = AiHelperTypoChecker;

/**
 * Factory: create and init a typo checker from a container element's data-config.
 * Also binds a check button if its ID matches the textarea-to-button map.
 *
 * @param {HTMLElement} container - Element with data-config (JSON: {endpoint, labels})
 * @param {string} textareaId - ID of the target textarea
 * @param {string} [buttonId] - If provided, bind the button's click to checkTypos()
 * @returns {AiHelperTypoChecker|null}
 */
AiHelperTypoChecker.initFromConfig = function(container, textareaId, buttonId) {
  if (!container) {return null;}
  const textarea = document.getElementById(textareaId);
  if (!textarea) {return null;}

  const config = JSON.parse(container.dataset.config || '{}');
  const checker = new AiHelperTypoChecker(textarea, {
    endpoint: config.endpoint,
    labels: config.labels
  });
  checker.init();

  // checker.init() already binds a click handler via findExistingButton()/
  // attachEventListeners() when buttonId matches the internal textarea-to-button
  // map, so only bind here for a custom button that init() did not find.
  if (buttonId) {
    const button = document.getElementById(buttonId);
    if (button && button !== checker.checkButton) {
      button.addEventListener('click', () => {
        checker.checkTypos();
      });
    }
  }

  return checker;
};