/**
 * AiHelperAssignmentSuggestion
 * Provides AI-powered assignee suggestions for Redmine issue forms.
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
    this.link.innerHTML = this.robotIconHtml + ' ' + this.labels.linkLabel;
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
      this.labels.loading +
      '</div>';

    parentP.parentNode.insertBefore(this.panel, parentP.nextSibling);
  }

  /**
   * Fetch assignee suggestions from the API.
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
          'X-CSRF-Token': csrfToken ? csrfToken.content : '',
        },
        body: JSON.stringify(body),
      });

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || 'Unknown error');
      }

      const data = await response.json();
      this.renderSuggestions(data);
    } catch (error) {
      console.error('Assignment suggestion error:', error);
      this.renderError(this.labels.error);
    }
  }

  /**
   * Render the suggestion results in the panel.
   * @param {Object} data - API response data
   */
  renderSuggestions(data) {
    if (!this.panel) return;

    let html = '';

    // History-based suggestions (with similar issues display)
    if (data.history_based && data.history_based.available) {
      html += this.renderHistoryCategory(
        this.labels.historyTitle,
        data.history_based.suggestions
      );
    }

    // Workload-based suggestions
    if (data.workload_based && data.workload_based.available) {
      html += this.renderCategory(
        this.labels.workloadTitle,
        data.workload_based.suggestions,
        (s) => this.labels.workloadOpenIssues + ': ' + s.open_issues_count + this.labels.workloadUnit
      );
    }

    // Instruction-based suggestions
    if (data.instruction_based && data.instruction_based.available) {
      html += this.renderCategory(
        this.labels.instructionTitle,
        data.instruction_based.suggestions,
        (s) => s.reason ? (this.labels.instructionReason + ': ' + s.reason) : ''
      );
    }

    // Close button
    html += '<div class="ai-helper-suggest-assignee-close">' +
      '<a href="#" class="ai-helper-suggest-assignee-close-btn">' + this.labels.close + '</a>' +
      '</div>';

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
   * Render the history-based category with similar issues.
   * @param {string} title - Category title
   * @param {Array} suggestions - Array of suggestion objects with similar_issues
   * @returns {string} HTML string
   */
  renderHistoryCategory(title, suggestions) {
    let html = '<div class="ai-helper-suggest-assignee-category">';
    html += '<div class="ai-helper-suggest-assignee-category-title">' + this.escapeHtml(title) + '</div>';

    if (!suggestions || suggestions.length === 0) {
      html += '<div class="ai-helper-suggest-assignee-no-results">' + this.labels.noSuggestions + '</div>';
    } else {
      html += '<ul class="ai-helper-suggest-assignee-list ai-helper-suggest-assignee-history-list">';
      suggestions.forEach((s, index) => {
        html += '<li class="ai-helper-suggest-assignee-history-item">';
        html += '<div class="ai-helper-suggest-assignee-user-row">';
        html += '<a href="#" class="ai-helper-suggest-assignee-user" data-user-id="' + s.user_id + '">';
        html += (index + 1) + '. ' + this.escapeHtml(s.user_name);
        html += '</a>';

        // Show score and count
        let detail = this.labels.historyScore + ': ' + s.score + '%';
        if (s.similar_issue_count) {
          detail += ' / ' + this.labels.historySimilarCount + ': ' + s.similar_issue_count;
        }
        html += ' <span class="ai-helper-suggest-assignee-detail">(' + this.escapeHtml(detail) + ')</span>';
        html += '</div>';

        // Render similar issues
        if (s.similar_issues && s.similar_issues.length > 0) {
          html += this.renderSimilarIssues(s.similar_issues);
        }

        html += '</li>';
      });
      html += '</ul>';
    }

    html += '</div>';
    return html;
  }

  /**
   * Render the list of similar issues for a suggested user.
   * @param {Array} similarIssues - Array of similar issue objects
   * @returns {string} HTML string
   */
  renderSimilarIssues(similarIssues) {
    let html = '<ul class="ai-helper-suggest-assignee-similar-issues">';

    similarIssues.forEach((issue) => {
      const issueUrl = this.getIssueUrl(issue.id);
      const score = Math.round(issue.similarity_score);
      html += '<li class="ai-helper-suggest-assignee-similar-issue">';
      html += '<a href="' + issueUrl + '" target="_blank" class="ai-helper-similar-issue-link">';
      html += '#' + issue.id + ' ' + this.escapeHtml(issue.subject || '');
      html += '</a>';
      html += ' <span class="ai-helper-similar-issue-score">(' + this.labels.historyScore + ': ' + score + '%)</span>';
      html += '</li>';
    });

    html += '</ul>';
    return html;
  }

  /**
   * Get the URL for an issue.
   * @param {number} issueId - The issue ID
   * @returns {string} Issue URL
   */
  getIssueUrl(issueId) {
    // Use Redmine's standard issue path
    return '/issues/' + issueId;
  }

  /**
   * Render a single category of suggestions.
   * @param {string} title - Category title
   * @param {Array} suggestions - Array of suggestion objects
   * @param {Function} detailFn - Function to generate detail text for each suggestion
   * @returns {string} HTML string
   */
  renderCategory(title, suggestions, detailFn) {
    let html = '<div class="ai-helper-suggest-assignee-category">';
    html += '<div class="ai-helper-suggest-assignee-category-title">' + title + '</div>';

    if (!suggestions || suggestions.length === 0) {
      html += '<div class="ai-helper-suggest-assignee-no-results">' + this.labels.noSuggestions + '</div>';
    } else {
      html += '<ul class="ai-helper-suggest-assignee-list">';
      suggestions.forEach((s, index) => {
        const detail = detailFn(s);
        html += '<li>';
        html += '<a href="#" class="ai-helper-suggest-assignee-user" data-user-id="' + s.user_id + '">';
        html += (index + 1) + '. ' + this.escapeHtml(s.user_name);
        html += '</a>';
        if (detail) {
          html += ' <span class="ai-helper-suggest-assignee-detail">(' + this.escapeHtml(detail) + ')</span>';
        }
        html += '</li>';
      });
      html += '</ul>';
    }

    html += '</div>';
    return html;
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
      '<a href="#" class="ai-helper-suggest-assignee-close-btn">' + this.labels.close + '</a>' +
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
   * @param {string} text
   * @returns {string}
   */
  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
}
