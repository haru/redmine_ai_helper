/**
 * AiHelperAssignmentSuggestion
 * Provides AI-powered assignee suggestions for Redmine issue forms.
 * HTML is rendered server-side via ERB templates for XSS protection.
 */
class AiHelperAssignmentSuggestion {
  /**
   * @param {Object} options
   * @param {string} options.endpoint - API endpoint URL
   * @param {Object} options.labels - I18n labels
   * @param {string} options.robotIconHtml - HTML for the robot icon SVG
   */
  constructor(options) {
    this.endpoint = options.endpoint;
    this.labels = options.labels;
    this.robotIconHtml = options.robotIconHtml || '';
    this.panel = null;
    this.link = null;
    this.isOpen = false;
  }

  /**
   * Initialize the suggestion feature by inserting the link into the DOM.
   */
  init() {
    const assignedToSelect = document.getElementById('issue_assigned_to_id');
    if (!assignedToSelect) return;

    const parentP = assignedToSelect.closest('p');
    if (!parentP) return;

    // Create the suggestion link
    this.link = document.createElement('a');
    this.link.className = 'ai-helper-suggest-assignee-link';
    this.link.href = '#';
    this.link.innerHTML = this.robotIconHtml + ' ' + this.escapeHtml(this.labels.linkLabel);
    this.link.addEventListener('click', (e) => {
      e.preventDefault();
      this.toggle();
    });

    parentP.appendChild(this.link);
  }

  /**
   * Toggle the suggestion panel visibility.
   */
  toggle() {
    if (this.isOpen) {
      this.close();
    } else {
      this.open();
    }
  }

  /**
   * Open the suggestion panel and fetch suggestions.
   */
  open() {
    this.isOpen = true;
    this.createPanel();
    this.fetchSuggestions();
  }

  /**
   * Close the suggestion panel.
   */
  close() {
    this.isOpen = false;
    if (this.panel) {
      this.panel.remove();
      this.panel = null;
    }
  }

  /**
   * Create the suggestion panel DOM element.
   */
  createPanel() {
    if (this.panel) {
      this.panel.remove();
    }

    const assignedToSelect = document.getElementById('issue_assigned_to_id');
    const parentP = assignedToSelect.closest('p');

    this.panel = document.createElement('div');
    this.panel.className = 'ai-helper-suggest-assignee-panel box';

    // Loading state
    this.panel.innerHTML = '<div class="ai-helper-suggest-assignee-loading">' +
      '<span class="ai-helper-spinner"></span> ' +
      this.escapeHtml(this.labels.loading) +
      '</div>';

    parentP.parentNode.insertBefore(this.panel, parentP.nextSibling);
  }

  /**
   * Fetch assignee suggestions from the API.
   * Server returns HTML rendered from ERB templates.
   */
  async fetchSuggestions() {
    const subjectInput = document.getElementById('issue_subject');
    const descriptionTextarea = document.getElementById('issue_description');
    const trackerSelect = document.getElementById('issue_tracker_id');
    const categorySelect = document.getElementById('issue_category_id');

    const subject = subjectInput ? subjectInput.value : '';
    const description = descriptionTextarea ? descriptionTextarea.value : '';

    if (!subject.trim() && !description.trim()) {
      this.renderError(this.labels.emptyContent);
      return;
    }

    const body = {
      subject: subject,
      description: description,
    };
    if (trackerSelect && trackerSelect.value) {
      body.tracker_id = parseInt(trackerSelect.value, 10);
    }
    if (categorySelect && categorySelect.value) {
      body.category_id = parseInt(categorySelect.value, 10);
    }

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]');
      const response = await fetch(this.endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'text/html',
          'X-CSRF-Token': csrfToken ? csrfToken.content : '',
        },
        body: JSON.stringify(body),
      });

      if (!response.ok) {
        throw new Error('Server error');
      }

      // Server returns HTML directly
      const html = await response.text();
      this.renderHtml(html);
    } catch (error) {
      console.error('Assignment suggestion error:', error);
      this.renderError(this.labels.error);
    }
  }

  /**
   * Render HTML from server response and bind event handlers.
   * @param {string} html - HTML string from server
   */
  renderHtml(html) {
    if (!this.panel) return;

    this.panel.innerHTML = html;

    // Bind click events for user selection
    this.panel.querySelectorAll('.ai-helper-suggest-assignee-user').forEach((el) => {
      el.addEventListener('click', (e) => {
        e.preventDefault();
        const userId = el.dataset.userId;
        this.selectUser(userId);
      });
    });

    // Bind close button
    const closeBtn = this.panel.querySelector('.ai-helper-suggest-assignee-close-btn');
    if (closeBtn) {
      closeBtn.addEventListener('click', (e) => {
        e.preventDefault();
        this.close();
      });
    }
  }

  /**
   * Select a user and set the assigned_to select box value.
   * @param {string} userId - The user ID to select
   */
  selectUser(userId) {
    const assignedToSelect = document.getElementById('issue_assigned_to_id');
    if (!assignedToSelect) return;

    // Set the select value
    assignedToSelect.value = userId;

    // Trigger change event for Redmine's UI updates
    const event = new Event('change', { bubbles: true });
    assignedToSelect.dispatchEvent(event);

    // Update the "assign to me" link visibility
    const assignToMeLink = document.querySelector('.assign-to-me-link');
    if (assignToMeLink) {
      const currentUserId = assignToMeLink.dataset.id;
      if (currentUserId === userId) {
        assignToMeLink.style.display = 'none';
      } else {
        assignToMeLink.style.display = '';
      }
    }
  }

  /**
   * Render an error message in the panel.
   * @param {string} message - Error message to display
   */
  renderError(message) {
    if (!this.panel) return;
    this.panel.innerHTML = '<div class="ai-helper-suggest-assignee-error">' +
      this.escapeHtml(message) +
      '</div>' +
      '<div class="ai-helper-suggest-assignee-close">' +
      '<a href="#" class="ai-helper-suggest-assignee-close-btn">' + this.escapeHtml(this.labels.close) + '</a>' +
      '</div>';

    const closeBtn = this.panel.querySelector('.ai-helper-suggest-assignee-close-btn');
    if (closeBtn) {
      closeBtn.addEventListener('click', (e) => {
        e.preventDefault();
        this.close();
      });
    }
  }

  /**
   * Escape HTML special characters to prevent XSS.
   * Only used for client-side labels in loading/error states.
   * @param {string} text
   * @returns {string}
   */
  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
}
