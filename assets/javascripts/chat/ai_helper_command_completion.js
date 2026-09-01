// Chat input area command completion functionality
(function() {
  const COMMAND_PREFIX = '/';

  /**
   * Slash-command autocompletion for the chat input: shows matching command
   * suggestions as the user types and lets them accept one via click or
   * keyboard.
   */
  class CommandCompletion {
    /**
     * @param {HTMLElement} inputElement - The chat message input.
     * @param {string|null} [commandsUrl] - Endpoint returning commands matching a prefix.
     */
    constructor(inputElement, commandsUrl = null) {
      this.input = inputElement;
      this.commandsUrl = commandsUrl;
      this.suggestionBox = null;
      this.commands = [];
      this.selectedIndex = -1;

      // Store reference on the input element for external access
      this.input._commandCompletion = this;

      this.init();
    }

    /**
     * Build the suggestion box and wire up event listeners.
     */
    init() {
      this.createSuggestionBox();
      this.attachEventListeners();
    }

    /**
     * Create and insert the (initially hidden) suggestion box element.
     */
    createSuggestionBox() {
      this.suggestionBox = document.createElement('div');
      this.suggestionBox.className = 'ai-helper-command-suggestions';
      this.suggestionBox.style.display = 'none';
      this.input.parentElement.appendChild(this.suggestionBox);
    }

    /**
     * Bind input/keydown handlers on the chat input and an outside-click
     * handler on the document to dismiss suggestions.
     */
    attachEventListeners() {
      this.input.addEventListener('input', this.handleInput.bind(this));
      this.input.addEventListener('keydown', this.handleKeyDown.bind(this));
      document.addEventListener('click', this.handleDocumentClick.bind(this));
    }

    /**
     * React to input changes: fetch and show command suggestions when the
     * input starts with `/`, otherwise hide them.
     */
    handleInput() {
      const value = this.input.value;

      if (!value.startsWith(COMMAND_PREFIX)) {
        this.hideSuggestions();
        return;
      }

      const commandPart = value.substring(1).split(/\s/)[0];
      this.fetchCommands(commandPart);
    }

    /**
     * Fetch commands matching a prefix from `commandsUrl` and show them.
     * @param {string} prefix - The text typed after `/`, up to the first whitespace.
     */
    async fetchCommands(prefix) {
      if (!this.commandsUrl) {
        return;
      }

      const url = this.commandsUrl;

      const params = new URLSearchParams({ prefix: prefix });

      try {
        const response = await fetch(`${url}?${params}`);
        const data = await response.json();
        this.commands = data.commands || [];
        this.showSuggestions();
      } catch (error) {
        console.error('Failed to fetch commands:', error);
        this.hideSuggestions();
      }
    }

    /**
     * Render the fetched commands into the suggestion box and reveal it.
     */
    showSuggestions() {
      if (this.commands.length === 0) {
        this.hideSuggestions();
        return;
      }

      this.suggestionBox.innerHTML = '';
      this.selectedIndex = -1;

      this.commands.forEach((command, index) => {
        const item = document.createElement('div');
        item.className = 'suggestion-item';

        const nameSpan = document.createElement('span');
        nameSpan.className = 'suggestion-command-name';
        nameSpan.textContent = `/${command.name}`;
        item.appendChild(nameSpan);

        if (command.description) {
          const descSpan = document.createElement('span');
          descSpan.className = 'suggestion-command-description';
          descSpan.textContent = command.description;
          item.appendChild(descSpan);
        }

        item.addEventListener('click', () => this.selectCommand(index));
        this.suggestionBox.appendChild(item);
      });

      this.suggestionBox.style.display = 'block';
    }

    /**
     * Hide the suggestion box and clear the selected index.
     */
    hideSuggestions() {
      this.suggestionBox.style.display = 'none';
      this.selectedIndex = -1;
    }

    /**
     * Returns whether the suggestion list is currently visible
     * @returns {boolean} True if the suggestion box is shown and non-empty.
     */
    isSuggestionsVisible() {
      return this.suggestionBox.style.display !== 'none' && this.commands.length > 0;
    }

    /**
     * Accept the current suggestion.
     * - If an item is selected via arrow keys, use that item
     * - If no item is selected, use the first suggestion
     * @returns {boolean} true if a suggestion was accepted
     */
    acceptSuggestion() {
      if (!this.isSuggestionsVisible()) {
        return false;
      }

      const index = this.selectedIndex >= 0 ? this.selectedIndex : 0;
      this.selectCommand(index);
      return true;
    }

    /**
     * Handle arrow-key navigation, Enter-to-accept, and Escape-to-dismiss
     * while suggestions are visible.
     * @param {KeyboardEvent} event - The keydown event.
     */
    handleKeyDown(event) {
      if (this.suggestionBox.style.display === 'none') {
        return;
      }

      switch (event.key) {
        case 'ArrowDown':
          event.preventDefault();
          this.moveSelection(1);
          break;
        case 'ArrowUp':
          event.preventDefault();
          this.moveSelection(-1);
          break;
        case 'Enter':
          if (this.isSuggestionsVisible()) {
            event.preventDefault();
            this.acceptSuggestion();
          }
          break;
        case 'Escape':
          this.hideSuggestions();
          break;
      }
    }

    /**
     * Move the highlighted suggestion by `direction`, clamped to the list bounds.
     * @param {number} direction - `1` to move down, `-1` to move up.
     */
    moveSelection(direction) {
      const items = this.suggestionBox.querySelectorAll('.suggestion-item');

      if (this.selectedIndex >= 0) {
        items[this.selectedIndex].classList.remove('selected');
      }

      this.selectedIndex = Math.max(0, Math.min(this.commands.length - 1, this.selectedIndex + direction));
      items[this.selectedIndex].classList.add('selected');
      items[this.selectedIndex].scrollIntoView({ block: 'nearest' });
    }

    /**
     * Replace the `/command` token in the input with the selected command,
     * preserving any text typed after it.
     * @param {number} index - Index of the command in `this.commands`.
     */
    selectCommand(index) {
      const command = this.commands[index];
      const currentValue = this.input.value;
      const afterCommand = currentValue.substring(1).split(/\s/).slice(1).join(' ');

      this.input.value = `/${command.name}${afterCommand ? ' ' + afterCommand : ''}`;
      this.hideSuggestions();
      this.input.focus();
    }

    /**
     * Dismiss the suggestion box when a click lands outside it and the input.
     * @param {MouseEvent} event - The document click event.
     */
    handleDocumentClick(event) {
      if (!this.suggestionBox.contains(event.target) && event.target !== this.input) {
        this.hideSuggestions();
      }
    }

  }

  // Make CommandCompletion available globally
  window.CommandCompletion = CommandCompletion;

  // Initialize on DOMContentLoaded
  document.addEventListener('DOMContentLoaded', function() {
    const chatInput = document.getElementById('ai-helper-message-input');
    if (chatInput && !chatInput.dataset.commandCompletionInitialized) {
      const commandsUrl = chatInput.dataset.commandsUrl;
      new window.CommandCompletion(chatInput, commandsUrl);
      chatInput.dataset.commandCompletionInitialized = 'true';
    }
  });
})();
