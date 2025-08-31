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
    this.overlayContainer = null;
    this.isEnabled = false;
    this.checkButton = null;
  }

  init() {
    this.createOverlay();
    this.createCheckButton();
    this.attachEventListeners();
  }

  createOverlay() {
    this.overlayContainer = document.createElement('div');
    this.overlayContainer.className = 'ai-helper-typo-overlay';
    this.overlayContainer.style.display = 'none';
    
    const textareaContainer = this.textarea.parentNode;
    textareaContainer.style.position = 'relative';
    textareaContainer.appendChild(this.overlayContainer);
  }

  createCheckButton() {
    const buttonContainer = document.createElement('div');
    buttonContainer.className = 'ai-helper-typo-controls';
    buttonContainer.style.textAlign = 'right';
    buttonContainer.style.marginTop = '5px';
    
    this.checkButton = document.createElement('button');
    this.checkButton.type = 'button';
    this.checkButton.className = 'typo-check-btn';
    this.checkButton.textContent = this.options.labels.checkButton || 'Check';
    
    buttonContainer.appendChild(this.checkButton);
    
    const textareaContainer = this.textarea.parentNode;
    textareaContainer.appendChild(buttonContainer);
  }

  attachEventListeners() {
    if (this.checkButton) {
      this.checkButton.addEventListener('click', () => {
        this.checkTypos();
      });
    }

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && this.overlayContainer.style.display === 'block') {
        this.hideOverlay();
      }
    });

    document.addEventListener('click', (e) => {
      if (this.overlayContainer.style.display === 'block' && 
          !this.overlayContainer.contains(e.target) && 
          e.target !== this.checkButton) {
        this.hideOverlay();
      }
    });

    this.textarea.addEventListener('input', () => {
      if (this.overlayContainer.style.display === 'block') {
        this.hideOverlay();
      }
    });
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
      this.displaySuggestions();
    } catch (error) {
      console.error('Typo check failed:', error);
      this.showErrorMessage();
    } finally {
      this.checkButton.disabled = false;
      this.checkButton.textContent = this.options.labels.checkButton || 'Check';
    }
  }

  displaySuggestions() {
    if (this.suggestions.length === 0) {
      this.showNoSuggestionsMessage();
      return;
    }

    this.overlayContainer.innerHTML = this.buildSuggestionsHTML();
    this.overlayContainer.style.display = 'block';
    this.attachSuggestionEventListeners();
  }

  buildSuggestionsHTML() {
    const html = `
      <div class="ai-helper-typo-suggestions">
        <div class="suggestions-header">
          <h4>${this.options.labels.suggestionsTitle || 'Correction Suggestions'}</h4>
          <button class="close-btn" data-action="close">&times;</button>
        </div>
        <div class="suggestions-list">
          ${this.suggestions.map((suggestion, index) => this.buildSuggestionItem(suggestion, index)).join('')}
        </div>
        <div class="suggestions-footer">
          <button class="accept-all-btn" data-action="accept-all">${this.options.labels.acceptAll || 'Accept All'}</button>
          <button class="dismiss-all-btn" data-action="dismiss-all">${this.options.labels.dismissAll || 'Dismiss All'}</button>
        </div>
      </div>
    `;
    return html;
  }

  buildSuggestionItem(suggestion, index) {
    return `
      <div class="suggestion-item" data-index="${index}">
        <div class="suggestion-content">
          <span class="original-text">${this.escapeHTML(suggestion.original)}</span>
          <span class="arrow">&rarr;</span>
          <span class="corrected-text">${this.escapeHTML(suggestion.corrected)}</span>
        </div>
        <div class="suggestion-meta">
          <span class="reason">${this.escapeHTML(suggestion.reason)}</span>
          <span class="confidence confidence-${suggestion.confidence}">${suggestion.confidence}</span>
        </div>
        <div class="suggestion-actions">
          <button class="accept-btn" data-action="accept" data-index="${index}">${this.options.labels.acceptSuggestion || 'Accept'}</button>
          <button class="dismiss-btn" data-action="dismiss" data-index="${index}">${this.options.labels.dismissSuggestion || 'Dismiss'}</button>
        </div>
      </div>
    `;
  }

  attachSuggestionEventListeners() {
    this.overlayContainer.addEventListener('click', (e) => {
      const action = e.target.dataset.action;
      const index = e.target.dataset.index;

      switch (action) {
        case 'accept':
          this.acceptSuggestion(parseInt(index));
          break;
        case 'dismiss':
          this.dismissSuggestion(parseInt(index));
          break;
        case 'accept-all':
          this.acceptAllSuggestions();
          break;
        case 'dismiss-all':
          this.dismissAllSuggestions();
          break;
        case 'close':
          this.hideOverlay();
          break;
      }
    });
  }

  acceptSuggestion(index) {
    const suggestion = this.suggestions[index];
    if (!suggestion) return;

    const text = this.textarea.value;
    const newText = text.substring(0, suggestion.position) + 
                   suggestion.corrected + 
                   text.substring(suggestion.position + suggestion.length);
    
    this.textarea.value = newText;
    
    this.updateSuggestionsAfterEdit(suggestion.position, suggestion.length, suggestion.corrected.length);
    this.removeSuggestion(index);
  }

  dismissSuggestion(index) {
    this.removeSuggestion(index);
  }

  acceptAllSuggestions() {
    const sortedSuggestions = [...this.suggestions].sort((a, b) => b.position - a.position);
    
    let text = this.textarea.value;
    sortedSuggestions.forEach(suggestion => {
      text = text.substring(0, suggestion.position) + 
             suggestion.corrected + 
             text.substring(suggestion.position + suggestion.length);
    });
    
    this.textarea.value = text;
    this.hideOverlay();
  }

  dismissAllSuggestions() {
    this.hideOverlay();
  }

  removeSuggestion(index) {
    this.suggestions.splice(index, 1);
    if (this.suggestions.length === 0) {
      this.hideOverlay();
    } else {
      this.displaySuggestions();
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
    this.overlayContainer.style.display = 'none';
    this.suggestions = [];
  }

  showNoSuggestionsMessage() {
    this.overlayContainer.innerHTML = `
      <div class="ai-helper-no-suggestions">
        <div class="no-suggestions-content">
          <h4>${this.options.labels.noSuggestions || 'No typos or errors found'}</h4>
          <p>The text appears to be error-free.</p>
        </div>
      </div>
    `;
    this.overlayContainer.style.display = 'block';
    setTimeout(() => this.hideOverlay(), 3000);
  }

  showErrorMessage() {
    this.overlayContainer.innerHTML = `
      <div class="ai-helper-typo-error">
        <div class="error-content">
          <h4>${this.options.labels.errorOccurred || 'An error occurred'}</h4>
          <p>Please try again later.</p>
        </div>
      </div>
    `;
    this.overlayContainer.style.display = 'block';
    setTimeout(() => this.hideOverlay(), 3000);
  }

  escapeHTML(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }

  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
  }
}

window.AiHelperTypoChecker = AiHelperTypoChecker;