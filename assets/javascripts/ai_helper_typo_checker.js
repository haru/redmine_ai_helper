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
      if (!this.controlPanel) return;
      
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
    
    if (!this.checkButton) {
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

  displayTypoOverlay() {
    
    if (this.suggestions.length === 0) {
      this.showNoSuggestionsMessage();
      return;
    }

    // Only set up overlay if not already visible
    if (!this.isOverlayVisible) {
      // Disable autocomplete
      this.disableAutocompletion();

      // Update overlay position
      this.updateOverlayPosition();
      
      // Update control panel position and show it
      this.updateControlPanelPosition();
      this.controlPanel.classList.add('ai-helper-control-panel-positioned');

      // Get textarea background color for overlay
      const bgColor = this.getTextareaBackgroundColor();
      this.overlay.style.backgroundColor = bgColor;

      // Hide textarea text and show overlay content with suggestions
      this.textarea.classList.add('ai-helper-text-transparent');

      // Show overlay
      this.overlay.classList.add('ai-helper-typo-overlay-active');
      this.isOverlayVisible = true;

      // Sync scroll position with textarea
      this.overlay.scrollTop = this.textarea.scrollTop;
      this.overlay.scrollLeft = this.textarea.scrollLeft;
    }

    // Always rebuild content (this is needed when suggestions change)
    this.buildOverlayContent();
    
    // Check if scrolling is needed after content is built
    setTimeout(() => {
      this.checkAndEnableScrolling();
    }, 10);
  }

  buildOverlayContent() {
    const text = this.textarea.value;
    this.overlay.innerHTML = '';

    // Validate and correct suggestions by position 
    const validatedSuggestions = this.suggestions.map(suggestion => {
      const replacementLength = suggestion.length || suggestion.original.length;
      const actualText = text.substring(suggestion.position, suggestion.position + replacementLength);
      
      
      // Basic validation - position should be valid
      if (suggestion.position < 0 || 
          suggestion.position >= text.length ||
          !suggestion.original || 
          !suggestion.corrected) {
        return null;
      }
      
      // If text doesn't match, try to find the correct position
      if (actualText !== suggestion.original) {
        
        // Find all occurrences of the original text
        const allPositions = [];
        let searchPos = 0;
        while (searchPos < text.length) {
          const foundPos = text.indexOf(suggestion.original, searchPos);
          if (foundPos === -1) break;
          allPositions.push(foundPos);
          searchPos = foundPos + 1;
        }
        
        if (allPositions.length > 0) {
          // Choose the position closest to the original suggestion
          let bestPosition = allPositions[0];
          let minDistance = Math.abs(allPositions[0] - suggestion.position);
          
          for (const pos of allPositions) {
            const distance = Math.abs(pos - suggestion.position);
            if (distance < minDistance) {
              minDistance = distance;
              bestPosition = pos;
            }
          }
          
          // Create corrected suggestion
          return {
            ...suggestion,
            position: bestPosition
          };
        } else {
          return null;
        }
      }
      
      return suggestion;
    }).filter(s => s !== null);
    
    const sortedSuggestions = validatedSuggestions.sort((a, b) => a.position - b.position);

    // Group suggestions by position and original text to handle duplicates
    // Only group suggestions that have EXACTLY the same position AND original text
    const groupedSuggestions = [];
    sortedSuggestions.forEach(suggestion => {
      
      // Find existing group with EXACT same position and original text
      const existingGroup = groupedSuggestions.find(group => 
        group.position === suggestion.position && 
        group.original === suggestion.original &&
        group.length === (suggestion.length || suggestion.original.length)
      );
      
      if (existingGroup) {
        // Add this suggestion to existing group
        existingGroup.suggestions.push(suggestion);
        // Combine reasons - check both 'reason' and 'reasons' fields
        const newReasons = [];
        if (suggestion.reasons && suggestion.reasons.length > 0) {
          newReasons.push(...suggestion.reasons);
        } else if (suggestion.reason && suggestion.reason.trim()) {
          newReasons.push(suggestion.reason);
        }
        // Add new reasons that aren't already in the group
        newReasons.forEach(reason => {
          if (!existingGroup.reasons.includes(reason)) {
            existingGroup.reasons.push(reason);
          }
        });
        // Use the highest confidence suggestion as the primary corrected text
        if (suggestion.confidence === 'high' || 
            (suggestion.confidence === 'medium' && existingGroup.corrected === existingGroup.suggestions[0].corrected)) {
          existingGroup.corrected = suggestion.corrected;
        }
      } else {
        // Create new group - preserve both 'reason' and 'reasons' fields
        const newGroup = {
          position: suggestion.position,
          original: suggestion.original,
          corrected: suggestion.corrected,
          length: suggestion.length || suggestion.original.length,
          reasons: [],
          suggestions: [suggestion],
          confidence: suggestion.confidence
        };
        
        // Preserve reason information from the original suggestion
        if (suggestion.reasons && suggestion.reasons.length > 0) {
          newGroup.reasons = [...suggestion.reasons];
        } else if (suggestion.reason && suggestion.reason.trim()) {
          newGroup.reasons = [suggestion.reason];
        }
        
        groupedSuggestions.push(newGroup);
      }
    });


    // Update the main suggestions array with grouped data
    this.suggestions = groupedSuggestions;

    let currentPosition = 0;
    let overlayContent = document.createElement('div');
    overlayContent.classList.add('ai-helper-overlay-content');
    overlayContent.style.lineHeight = window.getComputedStyle(this.textarea).lineHeight;

    groupedSuggestions.forEach((suggestion, sortedIndex) => {
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
        beforeSpan.classList.add('ai-helper-text-black');
        overlayContent.appendChild(beforeSpan);
      }

      // Add the typo with strikethrough
      const typoSpan = document.createElement('span');
      typoSpan.className = 'ai-helper-typo-original';
      typoSpan.textContent = suggestion.original;
      typoSpan.classList.add('ai-helper-typo-span');
      
      // Add tooltip functionality for showing correction reasons
      // Always show tooltip - with reasons if available, or basic info otherwise
      
      // Handle both original reason field and grouped reasons array
      const reasonsArray = suggestion.reasons || (suggestion.reason && suggestion.reason.trim() ? [suggestion.reason] : []);
      const hasReasons = reasonsArray && reasonsArray.length > 0;
      
      // Create custom tooltip element
      const tooltip = document.createElement('div');
      tooltip.className = 'ai-helper-tooltip';
      
      if (hasReasons && reasonsArray.length > 1) {
        // Multiple reasons - show as bullet list
        tooltip.innerHTML = '• ' + reasonsArray.map(reason => 
          reason.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        ).join('<br>• ');
      } else if (hasReasons) {
        // Single reason - show as plain text
        tooltip.textContent = reasonsArray[0];
      } else {
        // No reasons - show basic correction info
        tooltip.innerHTML = `${this.options.labels.correctionTooltip}:<br><strong>"${suggestion.original.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}"</strong><br>↓<br><strong>"${suggestion.corrected.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}"</strong>`;
      }
      
      // Tooltip styling is now handled by CSS classes
      
      // Add arrow pointing upward (since tooltip is now below)
      const arrow = document.createElement('div');
      arrow.className = 'ai-helper-tooltip-arrow';
      tooltip.appendChild(arrow);
      
      typoSpan.appendChild(tooltip);
      
      // Add hover event listeners for showing/hiding tooltip
      typoSpan.addEventListener('mouseenter', () => {
        // Calculate tooltip position relative to the element
        const spanRect = typoSpan.getBoundingClientRect();
        const viewportWidth = window.innerWidth;
        const viewportHeight = window.innerHeight;
        
        // Position tooltip below the span
        tooltip.style.top = (spanRect.bottom + 5) + 'px';
        
        // Center horizontally, but adjust if it would go off-screen
        let leftPos = spanRect.left + (spanRect.width / 2);
        const tooltipWidth = 300; // Max width of tooltip
        
        if (leftPos - tooltipWidth/2 < 10) {
          // Too far left, align to left edge
          leftPos = 10 + tooltipWidth/2;
        } else if (leftPos + tooltipWidth/2 > viewportWidth - 10) {
          // Too far right, align to right edge
          leftPos = viewportWidth - 10 - tooltipWidth/2;
        }
        
        tooltip.style.left = leftPos + 'px';
        tooltip.style.transform = 'translateX(-50%)';
        
        // Check if tooltip would go below viewport
        const estimatedTooltipHeight = 60; // Rough estimate
        if (spanRect.bottom + estimatedTooltipHeight > viewportHeight - 20) {
          // Show above instead
          tooltip.style.top = (spanRect.top - estimatedTooltipHeight - 5) + 'px';
          // Change arrow direction
          arrow.classList.add('ai-helper-tooltip-arrow-up');
        } else {
          // Show below (default)
          // Default arrow direction (down) is handled by CSS class
        }
        
        tooltip.classList.add('ai-helper-tooltip-visible');
      });
      
      typoSpan.addEventListener('mouseleave', () => {
        tooltip.classList.remove('ai-helper-tooltip-visible');
      });
      
      overlayContent.appendChild(typoSpan);

      // Add the correction
      const correctionSpan = document.createElement('span');
      correctionSpan.className = 'ai-helper-typo-correction';
      correctionSpan.textContent = suggestion.corrected;
      correctionSpan.classList.add('ai-helper-correction-span');
      overlayContent.appendChild(correctionSpan);

      // Add accept/reject buttons
      const buttonsContainer = document.createElement('span');
      buttonsContainer.className = 'ai-helper-typo-buttons';
      buttonsContainer.classList.add('ai-helper-buttons-container');

      // Clone the accept button from ERB template
      const acceptBtnTemplate = document.querySelector('.ai-helper-typo-accept-btn-template');
      const acceptBtn = acceptBtnTemplate.cloneNode(true);
      acceptBtn.className = 'ai-helper-typo-accept-btn'; // Change class name
      acceptBtn.title = this.options.labels.acceptSuggestion || 'Accept';
      // Button styling handled by CSS classes
      // Use a closure to capture the suggestion object itself instead of index
      acceptBtn.addEventListener('click', (e) => {
        e.preventDefault(); // Prevent any form submission
        e.stopPropagation(); // Stop event bubbling
        this.acceptSuggestionBySuggestion(suggestion);
      });

      // Clone the reject button from ERB template
      const rejectBtnTemplate = document.querySelector('.ai-helper-typo-reject-btn-template');
      const rejectBtn = rejectBtnTemplate.cloneNode(true);
      rejectBtn.className = 'ai-helper-typo-reject-btn'; // Change class name
      rejectBtn.title = this.options.labels.dismissSuggestion || 'Reject';
      // Button styling handled by CSS classes
      rejectBtn.addEventListener('click', (e) => {
        e.preventDefault(); // Prevent any form submission
        e.stopPropagation(); // Stop event bubbling
        this.rejectSuggestionBySuggestion(suggestion);
      });

      buttonsContainer.appendChild(acceptBtn);
      buttonsContainer.appendChild(rejectBtn);
      overlayContent.appendChild(buttonsContainer);

      // Always use original.length for consistent position calculation
      currentPosition = suggestion.position + suggestion.original.length;
    });

    // Add remaining text after last suggestion
    if (currentPosition < text.length) {
      const remainingText = text.substring(currentPosition);
      const remainingSpan = document.createElement('span');
      remainingSpan.textContent = remainingText;
      remainingSpan.classList.add('ai-helper-text-black');
      overlayContent.appendChild(remainingSpan);
    }

    this.overlay.appendChild(overlayContent);
  }

  acceptSuggestion(index) {
    const suggestion = this.suggestions[index];
    if (!suggestion) {
      return;
    }

    // Set processing flag to prevent input event from hiding overlay
    this.isProcessingSuggestion = true;

    const text = this.textarea.value;
    
    // Verify the text matches what we expect at the position
    const actualText = text.substring(suggestion.position, suggestion.position + suggestion.original.length);
    
    // Validate that the text at the position matches what we expect
    if (actualText !== suggestion.original) {
      console.error('Text mismatch detected when applying suggestion!', {
        expected: suggestion.original,
        actual: actualText,
        position: suggestion.position
      });
      // Try to find the correct position one more time
      const correctPos = text.indexOf(suggestion.original);
      if (correctPos !== -1 && correctPos !== suggestion.position) {
        suggestion.position = correctPos;
      } else {
        alert(this.options.labels.applyFailed + ': ' + suggestion.original);
        this.isProcessingSuggestion = false;
        return;
      }
    }
    
    // Use original.length for safety - it's always accurate
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
      // Rebuild overlay with remaining suggestions - don't call displayTypoOverlay again
      this.buildOverlayContent();
    }

    // Trigger input event for any listeners
    this.textarea.dispatchEvent(new Event('input', { bubbles: true }));
    
    // Clear processing flag after a short delay
    setTimeout(() => {
      this.isProcessingSuggestion = false;
    }, 100);
  }

  acceptSuggestionBySuggestion(suggestion) {
    
    // Find the index of this suggestion group in the current array
    // Use a more flexible matching approach for grouped suggestions
    const index = this.suggestions.findIndex(s => 
      s.original === suggestion.original &&
      s.corrected === suggestion.corrected &&
      Math.abs(s.position - suggestion.position) <= 5 // Allow small position differences
    );
    
    if (index === -1) {
      console.error('Suggestion not found in current array:', suggestion);
      console.error('Available suggestions:', this.suggestions);
      return;
    }
    
    // Set processing flag to prevent input event from hiding overlay
    this.isProcessingSuggestion = true;

    const text = this.textarea.value;
    
    // Verify the text matches what we expect at the position
    const actualText = text.substring(suggestion.position, suggestion.position + suggestion.original.length);
    
    // Validate that the text at the position matches what we expect
    if (actualText !== suggestion.original) {
      console.error('Text mismatch detected when applying suggestion!', {
        expected: suggestion.original,
        actual: actualText,
        position: suggestion.position
      });
      // Try to find the correct position one more time
      const correctPos = text.indexOf(suggestion.original);
      if (correctPos !== -1 && correctPos !== suggestion.position) {
        suggestion.position = correctPos;
      } else {
        alert(this.options.labels.applyFailed + ': ' + suggestion.original);
        this.isProcessingSuggestion = false;
        return;
      }
    }
    
    // Use original.length for safety - it's always accurate
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
      // Rebuild overlay with remaining suggestions - don't call displayTypoOverlay again
      this.buildOverlayContent();
    }

    // Trigger input event for any listeners
    this.textarea.dispatchEvent(new Event('input', { bubbles: true }));
    
    // Clear processing flag after a short delay
    setTimeout(() => {
      this.isProcessingSuggestion = false;
    }, 100);
  }

  rejectSuggestionBySuggestion(suggestion) {
    
    // Set processing flag to prevent events from hiding overlay
    this.isProcessingSuggestion = true;
    
    // Find the index of this suggestion group in the current array
    // Use a more flexible matching approach for grouped suggestions
    const index = this.suggestions.findIndex(s => 
      s.original === suggestion.original &&
      s.corrected === suggestion.corrected &&
      Math.abs(s.position - suggestion.position) <= 5 // Allow small position differences
    );
    
    if (index === -1) {
      console.error('Suggestion not found in current array:', suggestion);
      console.error('Available suggestions:', this.suggestions);
      this.isProcessingSuggestion = false;
      return;
    }
    
    // Simply remove the suggestion without applying it
    this.suggestions.splice(index, 1);

    if (this.suggestions.length === 0) {
      this.hideOverlay();
    } else {
      // Rebuild overlay with remaining suggestions - don't call displayTypoOverlay again
      this.buildOverlayContent();
    }
    
    // Clear processing flag after a short delay
    setTimeout(() => {
      this.isProcessingSuggestion = false;
    }, 100);
  }

  rejectSuggestion(index) {
    // Simply remove the suggestion without applying it
    this.suggestions.splice(index, 1);

    if (this.suggestions.length === 0) {
      this.hideOverlay();
    } else {
      // Rebuild overlay with remaining suggestions - don't call displayTypoOverlay again
      this.buildOverlayContent();
    }
  }

  acceptAllSuggestions() {
    
    if (this.suggestions.length === 0) {
      this.hideOverlay();
      return;
    }

    // Set processing flag to prevent input event from hiding overlay
    this.isProcessingSuggestion = true;

    // Sort suggestions by position (descending) to apply from end to beginning
    // This prevents position shifts from affecting subsequent applications
    const sortedSuggestions = [...this.suggestions].sort((a, b) => b.position - a.position);
    
    let text = this.textarea.value;
    let successfulApplications = 0;
    
    sortedSuggestions.forEach(suggestion => {
      
      // Verify the text matches what we expect at the position
      const actualText = text.substring(suggestion.position, suggestion.position + suggestion.original.length);
      
      if (actualText === suggestion.original) {
        // Apply the suggestion
        text = text.substring(0, suggestion.position) + 
               suggestion.corrected + 
               text.substring(suggestion.position + suggestion.original.length);
        successfulApplications++;
      } else {
      }
    });
    
    // Update textarea with all changes
    this.textarea.value = text;
    
    // Clear all suggestions and hide overlay
    this.suggestions = [];
    this.hideOverlay();

    // Trigger input event for any listeners
    this.textarea.dispatchEvent(new Event('input', { bubbles: true }));
    
    // Clear processing flag
    setTimeout(() => {
      this.isProcessingSuggestion = false;
    }, 100);
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
      this.overlay.classList.remove('ai-helper-typo-overlay-active', 'ai-helper-typo-overlay-scrollable');
      this.overlay.innerHTML = '';
      this.overlay.style.backgroundColor = 'transparent';
      
      // Reset scrolling settings
      this.resetScrolling();
    }
    
    // Hide control panel
    if (this.controlPanel) {
      this.controlPanel.classList.remove('ai-helper-control-panel-positioned');
    }
    
    this.suggestions = [];
    this.textarea.classList.remove('ai-helper-text-transparent');
    this.isOverlayVisible = false;
    
    // Re-enable autocomplete
    this.enableAutocompletion();
  }

  showNoSuggestionsMessage() {
    this.updateOverlayPosition();
    const bgColor = this.getTextareaBackgroundColor();
    this.overlay.style.backgroundColor = bgColor;
    
    this.overlay.innerHTML = `
      <div class="box">
        <p>${this.options.labels.noSuggestions || 'No typos or errors found'}</p>
      </div>
    `;
    this.overlay.classList.add('ai-helper-typo-overlay-active');
    setTimeout(() => this.hideOverlay(), 3000);
  }

  showErrorMessage() {
    this.updateOverlayPosition();
    const bgColor = this.getTextareaBackgroundColor();
    this.overlay.style.backgroundColor = bgColor;
    
    this.overlay.innerHTML = `
      <div class="box">
        <div class="flash error">
          ${this.options.labels.errorOccurred || 'An error occurred'}. Please try again later.
        </div>
      </div>
    `;
    this.overlay.classList.add('ai-helper-typo-overlay-active');
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
    if (!this.overlay) return;
    
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
    if (!this.overlay) return;
    
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
    if (!this.overlay) return;
    
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
    if (!this.overlay || !this.scrollableClickHandler) return;
    
    this.overlay.removeEventListener('click', this.scrollableClickHandler);
    this.overlay.removeEventListener('keydown', this.scrollableKeydownHandler);
    this.scrollableClickHandler = null;
    this.scrollableKeydownHandler = null;
  }

}

window.AiHelperTypoChecker = AiHelperTypoChecker;