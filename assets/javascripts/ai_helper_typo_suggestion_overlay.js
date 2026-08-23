// Overlay content rendering and suggestion accept/reject interactions for
// AiHelperTypoChecker. Split out of ai_helper_typo_checker.js to keep that
// file under the max-lines ESLint limit (see ADR-027). A classic script
// can't split a single class body across files, so this file extends
// AiHelperTypoChecker's static/prototype surface after the class is
// declared instead — same behavior as if these were defined inline in the
// class body. Must load after ai_helper_typo_checker.js (which declares
// `window.AiHelperTypoChecker`).

// Find the occurrence of `original` closest to the suggestion's reported position
function findClosestPosition(positions, targetPosition) {
  let bestPosition = positions[0];
  let minDistance = Math.abs(positions[0] - targetPosition);

  for (const pos of positions) {
    const distance = Math.abs(pos - targetPosition);
    if (distance < minDistance) {
      minDistance = distance;
      bestPosition = pos;
    }
  }

  return bestPosition;
}

AiHelperTypoChecker.validateAndGroupSuggestions = function(suggestions, text) {
  const validatedSuggestions = suggestions.map(suggestion => {
    const replacementLength = suggestion.length || suggestion.original.length;
    const actualText = text.substring(suggestion.position, suggestion.position + replacementLength);

    if (suggestion.position < 0 ||
        suggestion.position >= text.length ||
        !suggestion.original ||
        !suggestion.corrected) {
      return null;
    }

    if (actualText !== suggestion.original) {
      const allPositions = [];
      let searchPos = 0;
      while (searchPos < text.length) {
        const foundPos = text.indexOf(suggestion.original, searchPos);
        if (foundPos === -1) {break;}
        allPositions.push(foundPos);
        searchPos = foundPos + 1;
      }

      if (allPositions.length > 0) {
        return {
          ...suggestion,
          position: findClosestPosition(allPositions, suggestion.position)
        };
      } else {
        return null;
      }
    }

    return suggestion;
  }).filter(s => s !== null);

  const sortedSuggestions = validatedSuggestions.sort((a, b) => a.position - b.position);

  const groupedSuggestions = [];
  sortedSuggestions.forEach(suggestion => {
    const existingGroup = groupedSuggestions.find(group =>
      group.position === suggestion.position &&
      group.original === suggestion.original &&
      group.length === (suggestion.length || suggestion.original.length)
    );

    if (existingGroup) {
      existingGroup.suggestions.push(suggestion);
      const newReasons = [];
      if (suggestion.reasons && suggestion.reasons.length > 0) {
        newReasons.push(...suggestion.reasons);
      } else if (suggestion.reason && suggestion.reason.trim()) {
        newReasons.push(suggestion.reason);
      }
      newReasons.forEach(reason => {
        if (!existingGroup.reasons.includes(reason)) {
          existingGroup.reasons.push(reason);
        }
      });
      if (suggestion.confidence === 'high' ||
          (suggestion.confidence === 'medium' && existingGroup.corrected === existingGroup.suggestions[0].corrected)) {
        existingGroup.corrected = suggestion.corrected;
      }
    } else {
      const newGroup = {
        position: suggestion.position,
        original: suggestion.original,
        corrected: suggestion.corrected,
        length: suggestion.length || suggestion.original.length,
        reasons: [],
        suggestions: [suggestion],
        confidence: suggestion.confidence
      };

      if (suggestion.reasons && suggestion.reasons.length > 0) {
        newGroup.reasons = [...suggestion.reasons];
      } else if (suggestion.reason && suggestion.reason.trim()) {
        newGroup.reasons = [suggestion.reason];
      }

      groupedSuggestions.push(newGroup);
    }
  });

  return groupedSuggestions;
};

AiHelperTypoChecker.applyAllSuggestionTexts = function(suggestions, text) {
  const sortedSuggestions = [...suggestions].sort((a, b) => b.position - a.position);
  let result = text;

  sortedSuggestions.forEach(suggestion => {
    const actualText = result.substring(suggestion.position, suggestion.position + suggestion.original.length);
    if (actualText === suggestion.original) {
      result = result.substring(0, suggestion.position) +
             suggestion.corrected +
             result.substring(suggestion.position + suggestion.original.length);
    }
  });

  return result;
};

AiHelperTypoChecker.updateSuggestionPositions = function(suggestions, editPosition, originalLength, newLength) {
  const lengthDiff = newLength - originalLength;
  return suggestions.map(suggestion => {
    if (suggestion.position > editPosition) {
      return { ...suggestion, position: suggestion.position + lengthDiff };
    }
    return suggestion;
  });
};

Object.assign(AiHelperTypoChecker.prototype, {
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
  },

  buildOverlayContent() {
    const text = this.textarea.value;
    this.overlay.innerHTML = '';

    const groupedSuggestions = AiHelperTypoChecker.validateAndGroupSuggestions(this.suggestions, text);

    // Update the main suggestions array with grouped data
    this.suggestions = groupedSuggestions;

    let currentPosition = 0;
    const overlayContent = document.createElement('div');
    overlayContent.classList.add('ai-helper-overlay-content');
    overlayContent.style.lineHeight = window.getComputedStyle(this.textarea).lineHeight;

    groupedSuggestions.forEach((suggestion) => {
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
  },

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
  },

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
  },

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
  },

  rejectSuggestion(index) {
    // Simply remove the suggestion without applying it
    this.suggestions.splice(index, 1);

    if (this.suggestions.length === 0) {
      this.hideOverlay();
    } else {
      // Rebuild overlay with remaining suggestions - don't call displayTypoOverlay again
      this.buildOverlayContent();
    }
  },

  acceptAllSuggestions() {

    if (this.suggestions.length === 0) {
      this.hideOverlay();
      return;
    }

    // Set processing flag to prevent input event from hiding overlay
    this.isProcessingSuggestion = true;

    this.textarea.value = AiHelperTypoChecker.applyAllSuggestionTexts(this.suggestions, this.textarea.value);

    // Clear all suggestions and hide overlay
    this.suggestions = [];
    this.hideOverlay();

    // Trigger input event for any listeners
    this.textarea.dispatchEvent(new Event('input', { bubbles: true }));

    // Clear processing flag
    setTimeout(() => {
      this.isProcessingSuggestion = false;
    }, 100);
  },

  updateSuggestionsAfterEdit(editPosition, originalLength, newLength) {
    this.suggestions = AiHelperTypoChecker.updateSuggestionPositions(
      this.suggestions, editPosition, originalLength, newLength
    );
  },

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
  },

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
  },

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
  },
});
