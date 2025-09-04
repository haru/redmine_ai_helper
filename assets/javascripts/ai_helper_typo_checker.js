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
      console.warn('Typo control panel not found for textarea:', this.textarea.id);
      return;
    }

    // Position panel at bottom-right of textarea
    const parent = this.textarea.parentNode;
    if (window.getComputedStyle(parent).position === 'static') {
      parent.style.position = 'relative';
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
      // Remove any existing event listeners to prevent duplicates
      this.checkButton.removeEventListener('click', this.checkTyposHandler);
      
      // Create bound handler for later removal
      this.checkTyposHandler = () => {
        console.log('Check button clicked');
        this.checkTypos();
      };
      
      this.checkButton.addEventListener('click', this.checkTyposHandler);
    }

    // Hide overlay when user starts typing or clicks outside
    this.textarea.addEventListener('input', () => {
      console.log('Input event triggered, isProcessingSuggestion:', this.isProcessingSuggestion, 'overlay display:', this.overlay ? this.overlay.style.display : 'no overlay');
      if (this.isProcessingSuggestion) {
        console.log('Ignoring input event during suggestion processing');
        return;
      }
      if (this.overlay && this.overlay.style.display === 'block') {
        console.log('Hiding overlay due to input event');
        this.hideOverlay();
      }
    });

    document.addEventListener('keydown', (e) => {
      console.log('Keydown event, key:', e.key, 'isProcessingSuggestion:', this.isProcessingSuggestion);
      if (this.isProcessingSuggestion) {
        console.log('Ignoring keydown during suggestion processing');
        return;
      }
      if (e.key === 'Escape' && this.overlay && this.overlay.style.display === 'block') {
        console.log('Hiding overlay due to Escape key');
        this.hideOverlay();
      }
    });

    document.addEventListener('click', (e) => {
      console.log('Document click event, target:', e.target, 'isProcessingSuggestion:', this.isProcessingSuggestion);
      if (this.isProcessingSuggestion) {
        console.log('Ignoring document click during suggestion processing');
        return;
      }
      if (this.overlay && this.overlay.style.display === 'block' && 
          !this.overlay.contains(e.target) && 
          e.target !== this.checkButton &&
          e.target !== this.textarea) {
        console.log('Hiding overlay due to document click outside overlay');
        this.hideOverlay();
      }
    });

    // Disable autocomplete when typo overlay is active
    this.textarea.addEventListener('focus', () => {
      if (this.overlay && this.overlay.style.display === 'block') {
        this.disableAutocompletion();
      }
    });

    // Sync overlay scroll with textarea scroll
    this.textarea.addEventListener('scroll', () => {
      this.syncScroll();
    });
  }

  disableAutocompletion() {
    console.log('disableAutocompletion called, isProcessingSuggestion:', this.isProcessingSuggestion);
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
    console.log('checkTypos called, isCheckingTypos:', this.isCheckingTypos);
    
    // Prevent duplicate execution
    if (this.isCheckingTypos) {
      console.log('Already checking typos, skipping duplicate call');
      return;
    }
    
    const text = this.textarea.value;
    console.log('Text content being checked:', JSON.stringify(text));
    
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
      console.log('Making API request to:', this.options.endpoint);
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
      console.log('Received suggestions:', data.suggestions);
      console.log('First suggestion detail:', data.suggestions && data.suggestions[0]);
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
    console.log('displayTypoOverlay called, isOverlayVisible:', this.isOverlayVisible, 'suggestions count:', this.suggestions.length);
    console.trace('displayTypoOverlay call stack');
    
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
      this.controlPanel.style.display = 'block';

      // Get textarea background color for overlay
      const bgColor = this.getTextareaBackgroundColor();
      this.overlay.style.backgroundColor = bgColor;

      // Hide textarea text and show overlay content with suggestions
      this.textarea.style.color = 'transparent';

      // Show overlay
      this.overlay.style.display = 'block';
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
    console.log('buildOverlayContent called, suggestions count:', this.suggestions.length);
    console.log('All suggestions:', this.suggestions);
    
    const text = this.textarea.value;
    console.log('Textarea text:', JSON.stringify(text), 'Length:', text.length);
    this.overlay.innerHTML = '';

    // Validate and correct suggestions by position 
    const validatedSuggestions = this.suggestions.map(suggestion => {
      const replacementLength = suggestion.length || suggestion.original.length;
      const actualText = text.substring(suggestion.position, suggestion.position + replacementLength);
      
      console.log('Validating suggestion:', {
        original: suggestion.original,
        actualText: actualText,
        position: suggestion.position,
        length: replacementLength,
        matches: actualText === suggestion.original
      });
      
      // Basic validation - position should be valid
      if (suggestion.position < 0 || 
          suggestion.position >= text.length ||
          !suggestion.original || 
          !suggestion.corrected) {
        console.warn('Invalid suggestion detected (basic validation failed):', suggestion);
        return null;
      }
      
      // If text doesn't match, try to find the correct position
      if (actualText !== suggestion.original) {
        console.log('Text mismatch, searching for correct position...');
        
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
          
          console.log('Found correct position for', suggestion.original, 'at', bestPosition, 'instead of', suggestion.position, '(all positions:', allPositions, ')');
          // Create corrected suggestion
          return {
            ...suggestion,
            position: bestPosition
          };
        } else {
          console.warn('Could not find', suggestion.original, 'in text. Skipping suggestion.');
          return null;
        }
      }
      
      return suggestion;
    }).filter(s => s !== null);
    
    const sortedSuggestions = validatedSuggestions.sort((a, b) => a.position - b.position);
    console.log('All suggestions after filtering:', sortedSuggestions.length, 'out of', this.suggestions.length);
    console.log('Sample filtered suggestion:', sortedSuggestions[0]);

    // Group suggestions by position and original text to handle duplicates
    // Only group suggestions that have EXACTLY the same position AND original text
    const groupedSuggestions = [];
    sortedSuggestions.forEach(suggestion => {
      console.log('Processing suggestion for grouping:', {
        original: suggestion.original,
        corrected: suggestion.corrected,
        reason: suggestion.reason,
        position: suggestion.position,
        length: suggestion.length
      });
      
      // Find existing group with EXACT same position and original text
      const existingGroup = groupedSuggestions.find(group => 
        group.position === suggestion.position && 
        group.original === suggestion.original &&
        group.length === (suggestion.length || suggestion.original.length)
      );
      
      if (existingGroup) {
        console.log('Found existing group at same position with same text, merging...');
        // Add this suggestion to existing group
        existingGroup.suggestions.push(suggestion);
        // Combine reasons
        if (suggestion.reason && suggestion.reason.trim() && !existingGroup.reasons.includes(suggestion.reason)) {
          existingGroup.reasons.push(suggestion.reason);
        }
        // Use the highest confidence suggestion as the primary corrected text
        if (suggestion.confidence === 'high' || 
            (suggestion.confidence === 'medium' && existingGroup.corrected === existingGroup.suggestions[0].corrected)) {
          existingGroup.corrected = suggestion.corrected;
        }
        console.log('Added to existing group, updated reasons:', existingGroup.reasons);
      } else {
        console.log('Creating new group for unique position/text combination');
        // Create new group
        const newGroup = {
          position: suggestion.position,
          original: suggestion.original,
          corrected: suggestion.corrected,
          length: suggestion.length || suggestion.original.length,
          reasons: (suggestion.reason && suggestion.reason.trim()) ? [suggestion.reason] : [],
          suggestions: [suggestion],
          confidence: suggestion.confidence
        };
        groupedSuggestions.push(newGroup);
        console.log('Created new group with reasons:', newGroup.reasons);
      }
    });

    console.log('Grouped suggestions:', groupedSuggestions.length, 'groups from', sortedSuggestions.length, 'suggestions');
    console.log('Sample grouped suggestion:', groupedSuggestions[0]);

    // Update the main suggestions array with grouped data
    this.suggestions = groupedSuggestions;

    let currentPosition = 0;
    let overlayContent = document.createElement('div');
    overlayContent.style.position = 'relative';
    overlayContent.style.lineHeight = window.getComputedStyle(this.textarea).lineHeight;

    groupedSuggestions.forEach((suggestion, sortedIndex) => {
      // Find the original index in this.suggestions array
      const originalIndex = this.suggestions.findIndex(s => 
        s.position === suggestion.position && 
        s.original === suggestion.original &&
        s.corrected === suggestion.corrected
      );
      
      console.log('Building suggestion at sortedIndex:', sortedIndex, 'originalIndex:', originalIndex, 'suggestion:', suggestion);
      console.log('Current position:', currentPosition, 'Suggestion position:', suggestion.position, 'Original text:', suggestion.original, 'Original length:', suggestion.original.length);

      // Add text before the typo
      if (currentPosition < suggestion.position) {
        const beforeText = text.substring(currentPosition, suggestion.position);
        console.log('Before text:', JSON.stringify(beforeText), 'Length:', beforeText.length);
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
      typoSpan.style.cursor = 'help';
      typoSpan.style.position = 'relative';
      
      // Add tooltip functionality for showing correction reasons
      // Always show tooltip - with reasons if available, or basic info otherwise
      console.log('Creating tooltip for suggestion:', {
        original: suggestion.original,
        corrected: suggestion.corrected,
        reason: suggestion.reason,
        reasons: suggestion.reasons,
        hasOriginalReason: suggestion.reason && suggestion.reason.trim(),
        hasReasonsArray: suggestion.reasons && suggestion.reasons.length > 0
      });
      
      // Handle both original reason field and grouped reasons array
      const reasonsArray = suggestion.reasons || (suggestion.reason && suggestion.reason.trim() ? [suggestion.reason] : []);
      const hasReasons = reasonsArray && reasonsArray.length > 0;
      
      // Create custom tooltip element
      const tooltip = document.createElement('div');
      tooltip.className = 'ai-helper-typo-tooltip';
      
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
        tooltip.innerHTML = `修正候補:<br><strong>"${suggestion.original.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}"</strong><br>↓<br><strong>"${suggestion.corrected.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}"</strong>`;
      }
      
      // Style the tooltip (moved outside the if block)
      tooltip.style.display = 'none';
      tooltip.style.position = 'fixed'; // Use fixed positioning to avoid overlay clipping
      tooltip.style.top = '100%';
      tooltip.style.left = '50%';
      tooltip.style.transform = 'translateX(-50%)';
      tooltip.style.backgroundColor = '#333';
      tooltip.style.color = 'white';
      tooltip.style.padding = '8px 12px';
      tooltip.style.borderRadius = '4px';
      tooltip.style.fontSize = '12px';
      tooltip.style.lineHeight = '1.4';
      tooltip.style.zIndex = '10001'; // Higher than overlay
      tooltip.style.boxShadow = '0 2px 8px rgba(0,0,0,0.15)';
      tooltip.style.marginTop = '5px';
      tooltip.style.maxWidth = '300px';
      tooltip.style.whiteSpace = 'normal';
      tooltip.style.textAlign = 'left';
      tooltip.style.overflowWrap = 'break-word';
      tooltip.style.pointerEvents = 'none'; // Prevent interference with mouse events
      
      // Add arrow pointing upward (since tooltip is now below)
      const arrow = document.createElement('div');
      arrow.style.position = 'absolute';
      arrow.style.bottom = '100%';
      arrow.style.left = '50%';
      arrow.style.marginLeft = '-5px';
      arrow.style.borderWidth = '5px';
      arrow.style.borderStyle = 'solid';
      arrow.style.borderColor = 'transparent transparent #333 transparent';
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
          arrow.style.bottom = 'auto';
          arrow.style.top = '100%';
          arrow.style.borderColor = '#333 transparent transparent transparent';
        } else {
          // Show below (default)
          arrow.style.top = 'auto';
          arrow.style.bottom = '100%';
          arrow.style.borderColor = 'transparent transparent #333 transparent';
        }
        
        tooltip.style.display = 'block';
      });
      
      typoSpan.addEventListener('mouseleave', () => {
        tooltip.style.display = 'none';
      });
      
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

      // Clone the accept button from ERB template
      const acceptBtnTemplate = document.querySelector('.ai-helper-typo-accept-btn-template');
      const acceptBtn = acceptBtnTemplate.cloneNode(true);
      acceptBtn.className = 'ai-helper-typo-accept-btn'; // Change class name
      acceptBtn.title = this.options.labels.acceptSuggestion || 'Accept';
      acceptBtn.style.cssText = `
        margin-right: 2px;
        cursor: pointer;
      `;
      // Use a closure to capture the suggestion object itself instead of index
      acceptBtn.addEventListener('click', (e) => {
        e.preventDefault(); // Prevent any form submission
        e.stopPropagation(); // Stop event bubbling
        console.log('ACCEPT button clicked for suggestion:', suggestion.original);
        this.acceptSuggestionBySuggestion(suggestion);
      });

      // Clone the reject button from ERB template
      const rejectBtnTemplate = document.querySelector('.ai-helper-typo-reject-btn-template');
      const rejectBtn = rejectBtnTemplate.cloneNode(true);
      rejectBtn.className = 'ai-helper-typo-reject-btn'; // Change class name
      rejectBtn.title = this.options.labels.dismissSuggestion || 'Reject';
      rejectBtn.style.cssText = `
        cursor: pointer;
      `;
      rejectBtn.addEventListener('click', (e) => {
        e.preventDefault(); // Prevent any form submission
        e.stopPropagation(); // Stop event bubbling
        console.log('REJECT button clicked for suggestion:', suggestion.original);
        this.rejectSuggestionBySuggestion(suggestion);
      });

      buttonsContainer.appendChild(acceptBtn);
      buttonsContainer.appendChild(rejectBtn);
      overlayContent.appendChild(buttonsContainer);

      // Always use original.length for consistent position calculation
      currentPosition = suggestion.position + suggestion.original.length;
      console.log('Original length:', suggestion.original.length, 'Updated currentPosition to:', currentPosition);
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
    console.log('acceptSuggestion called with index:', index);
    console.log('Current suggestions:', this.suggestions);
    
    const suggestion = this.suggestions[index];
    if (!suggestion) {
      console.log('No suggestion found at index:', index);
      return;
    }

    console.log('Accepting suggestion:', suggestion);

    // Set processing flag to prevent input event from hiding overlay
    this.isProcessingSuggestion = true;

    const text = this.textarea.value;
    
    // Verify the text matches what we expect at the position
    const actualText = text.substring(suggestion.position, suggestion.position + suggestion.original.length);
    console.log('Applying suggestion:', {
      position: suggestion.position,
      original: suggestion.original,
      corrected: suggestion.corrected,
      actualTextAtPosition: actualText,
      serverLength: suggestion.length,
      originalLength: suggestion.original.length
    });
    
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
        console.log('Found correct position, updating suggestion position from', suggestion.position, 'to', correctPos);
        suggestion.position = correctPos;
      } else {
        alert('修正適用に失敗しました。テキストの位置が見つかりません: ' + suggestion.original);
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
    
    console.log('Remaining suggestions after removal:', this.suggestions);

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
    console.log('*** ACCEPT SUGGESTION METHOD CALLED ***');
    console.log('acceptSuggestionBySuggestion called with suggestion:', suggestion);
    console.log('Current suggestions:', this.suggestions);
    
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
    
    console.log('Found suggestion at index:', index);
    
    // Set processing flag to prevent input event from hiding overlay
    this.isProcessingSuggestion = true;

    const text = this.textarea.value;
    
    // Verify the text matches what we expect at the position
    const actualText = text.substring(suggestion.position, suggestion.position + suggestion.original.length);
    console.log('Applying suggestion:', {
      position: suggestion.position,
      original: suggestion.original,
      corrected: suggestion.corrected,
      actualTextAtPosition: actualText,
      serverLength: suggestion.length,
      originalLength: suggestion.original.length
    });
    
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
        console.log('Found correct position, updating suggestion position from', suggestion.position, 'to', correctPos);
        suggestion.position = correctPos;
      } else {
        alert('修正適用に失敗しました。テキストの位置が見つかりません: ' + suggestion.original);
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
    
    console.log('Remaining suggestions after removal:', this.suggestions);

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
    console.log('*** REJECT SUGGESTION METHOD CALLED ***');
    console.log('rejectSuggestionBySuggestion called with suggestion:', suggestion);
    
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
    
    console.log('Found suggestion at index:', index, 'removing it');
    
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
    console.log('acceptAllSuggestions called, suggestions count:', this.suggestions.length);
    
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
      console.log('Applying suggestion:', suggestion);
      
      // Verify the text matches what we expect at the position
      const actualText = text.substring(suggestion.position, suggestion.position + suggestion.original.length);
      
      if (actualText === suggestion.original) {
        // Apply the suggestion
        text = text.substring(0, suggestion.position) + 
               suggestion.corrected + 
               text.substring(suggestion.position + suggestion.original.length);
        successfulApplications++;
        console.log('Successfully applied suggestion:', suggestion.original, '->', suggestion.corrected);
      } else {
        console.warn('Skipping suggestion due to text mismatch:', {
          expected: suggestion.original,
          actual: actualText,
          position: suggestion.position
        });
      }
    });
    
    // Update textarea with all changes
    this.textarea.value = text;
    
    console.log('Applied', successfulApplications, 'out of', sortedSuggestions.length, 'suggestions');
    
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
    console.log('hideOverlay called');
    console.trace('hideOverlay call stack');
    if (this.overlay) {
      this.overlay.style.display = 'none';
      this.overlay.innerHTML = '';
      this.overlay.style.backgroundColor = 'transparent';
      
      // Reset scrolling settings
      this.resetScrolling();
    }
    
    // Hide control panel
    if (this.controlPanel) {
      this.controlPanel.style.display = 'none';
    }
    
    this.suggestions = [];
    this.textarea.style.color = '';
    this.isOverlayVisible = false;
    
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
    
    // Debug logging
    console.log('TypoChecker Debug - contentHeight:', contentHeight, 'overlayHeight:', overlayHeight);
    
    if (contentHeight > overlayHeight) {
      console.log('TypoChecker Debug - Enabling scrolling mode');
      // Content exceeds height, enable scrolling
      this.overlay.style.overflowY = 'auto';
      this.overlay.style.overflowX = 'hidden';
      
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
      
      console.log('TypoChecker Debug - Scrolling enabled, z-index:', this.overlay.style.zIndex, 'pointerEvents:', this.overlay.style.pointerEvents);
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