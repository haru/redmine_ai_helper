// Chat input area command completion functionality
(function() {
  const COMMAND_PREFIX = '/';

  // Make CommandCompletion class available globally for dynamic initialization
  class CommandCompletion {
    constructor(inputElement, projectId = null) {
      this.input = inputElement;
      this.projectId = projectId;
      this.suggestionBox = null;
      this.commands = [];
      this.selectedIndex = -1;

      // Store reference on the input element for external access
      this.input._commandCompletion = this;

      this.init();
    }

    init() {
      this.createSuggestionBox();
      this.attachEventListeners();
    }

    createSuggestionBox() {
      this.suggestionBox = document.createElement('div');
      this.suggestionBox.className = 'ai-helper-command-suggestions';
      this.suggestionBox.style.display = 'none';
      this.input.parentElement.appendChild(this.suggestionBox);
    }

    attachEventListeners() {
      this.input.addEventListener('input', this.handleInput.bind(this));
      this.input.addEventListener('keydown', this.handleKeyDown.bind(this));
      document.addEventListener('click', this.handleDocumentClick.bind(this));
    }

    handleInput(event) {
      const value = this.input.value;

      if (!value.startsWith(COMMAND_PREFIX)) {
        this.hideSuggestions();
        return;
      }

      const commandPart = value.substring(1).split(/\s/)[0];
      this.fetchCommands(commandPart);
    }

    async fetchCommands(prefix) {
      const url = this.projectId
        ? `/ai_helper/projects/${this.projectId}/custom_commands/available`
        : '/ai_helper/custom_commands/available';

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
        item.textContent = `/${command.name}`;
        item.addEventListener('click', () => this.selectCommand(index));
        this.suggestionBox.appendChild(item);
      });

      this.suggestionBox.style.display = 'block';
    }

    hideSuggestions() {
      this.suggestionBox.style.display = 'none';
      this.selectedIndex = -1;
    }

    /**
     * Returns whether the suggestion list is currently visible
     * @returns {boolean}
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

    moveSelection(direction) {
      const items = this.suggestionBox.querySelectorAll('.suggestion-item');

      if (this.selectedIndex >= 0) {
        items[this.selectedIndex].classList.remove('selected');
      }

      this.selectedIndex = Math.max(0, Math.min(this.commands.length - 1, this.selectedIndex + direction));
      items[this.selectedIndex].classList.add('selected');
      items[this.selectedIndex].scrollIntoView({ block: 'nearest' });
    }

    selectCommand(index) {
      const command = this.commands[index];
      const currentValue = this.input.value;
      const afterCommand = currentValue.substring(1).split(/\s/).slice(1).join(' ');

      this.input.value = `/${command.name}${afterCommand ? ' ' + afterCommand : ''}`;
      this.hideSuggestions();
      this.input.focus();
    }

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
      const projectId = chatInput.dataset.projectId;
      new window.CommandCompletion(chatInput, projectId);
      chatInput.dataset.commandCompletionInitialized = 'true';
    }
  });
})();
