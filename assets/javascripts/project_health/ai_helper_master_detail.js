// Master-Detail Layout Management for Health Report History
// Handles report selection, Ajax loading, and dynamic interactions

// Guard against multiple script loading
if (typeof window.AiHelperMasterDetail === 'undefined') {

/**
 * Master-detail layout controller for the project health report history:
 * report selection, AJAX detail loading/deletion, and export handlers.
 */
class AiHelperMasterDetail {
  /**
   * Initialize state and set up the layout if present on the page.
   */
  constructor() {
    this.selectedReportId = null;
    this.masterPane = null;
    this.detailPane = null;
    this.detailContainer = null;
    this.init();
  }

  /**
   * Locate the layout's panes and wire up event listeners, if the layout is
   * present on this page.
   */
  init() {
    if (!this.checkElements()) {
      return;
    }

    this.masterPane = document.querySelector('.ai-helper-master-pane');
    this.detailPane = document.querySelector('.ai-helper-detail-pane');
    this.detailContainer = document.getElementById('ai-helper-health-report-detail-container');

    this.attachEventListeners();
    this.initializeSelection();
  }

  /**
   * Check whether the master-detail layout is present on the current page.
   * @returns {boolean} True if the layout element exists.
   */
  checkElements() {
    const layout = document.querySelector('.ai-helper-master-detail-layout');
    return layout !== null;
  }

  /**
   * Bind click handlers for selecting a report row and deleting a report.
   */
  attachEventListeners() {
    // Clickable cell events (ID and created_on columns)
    const clickableCells = document.querySelectorAll('.ai-helper-clickable-cell');
    clickableCells.forEach(cell => {
      cell.addEventListener('click', (e) => {
        e.preventDefault();
        const row = cell.closest('.ai-helper-report-row');
        this.selectReport(row);
      });
    });

    // Delete button Ajax handling
    const deleteLinks = document.querySelectorAll('.ai-helper-report-row .icon-del');
    deleteLinks.forEach(link => {
      link.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        this.handleDelete(link);
      });
    });
  }

  /**
   * Restore `selectedReportId` from whichever row is already marked
   * selected (server-rendered on page load).
   */
  initializeSelection() {
    // Initialize with already selected report if any
    const selectedRow = document.querySelector('.ai-helper-report-row.selected');
    if (selectedRow) {
      this.selectedReportId = selectedRow.dataset.reportId;
    }
  }

  /**
   * Select a report row and render its detail from the row's own data
   * attributes (no AJAX round-trip needed).
   * @param {HTMLElement} row - The `.ai-helper-report-row` element clicked.
   */
  selectReport(row) {
    const reportId = row.dataset.reportId;
    const reportContent = row.dataset.reportContent;
    const createdAt = row.dataset.reportCreatedAt;
    const userName = row.dataset.reportUserName;

    if (this.selectedReportId === reportId) {
      return; // Already selected
    }

    // Update selection state
    this.updateSelection(row, reportId);

    // Display report detail directly from data attributes
    const data = {
      id: reportId,
      health_report: reportContent,
      created_at: createdAt,
      user: {
        name: userName
      }
    };

    this.renderReportDetail(data);
  }

  /**
   * Mark `row` as the selected report row and clear selection from the rest.
   * @param {HTMLElement} row - The row to select.
   * @param {string} reportId - The report's id, stored as the current selection.
   */
  updateSelection(row, reportId) {
    // Remove selection from all rows
    document.querySelectorAll('.ai-helper-report-row').forEach(r => {
      r.classList.remove('selected');
    });

    // Add selection to clicked row
    row.classList.add('selected');
    this.selectedReportId = reportId;
  }

  /**
   * Fetch a report's detail JSON via AJAX and render it.
   * @param {string} url - The report detail endpoint.
   */
  loadReportDetail(url) {
    // Show loading state
    this.showLoading();

    const xhr = new XMLHttpRequest();
    xhr.open('GET', url, true);
    xhr.setRequestHeader('Accept', 'application/json');

    xhr.onload = () => {
      if (xhr.status === 200) {
        try {
          const data = JSON.parse(xhr.responseText);
          this.renderReportDetail(data);
        } catch (error) {
          console.error('JSON parse error:', error);
          this.showError(this.getI18nText('error_loading_report', 'Failed to load report') + ': ' + error.message);
        }
      } else {
        console.error('HTTP error:', xhr.status, xhr.responseText);
        this.showError(this.getI18nText('error_loading_report', 'Failed to load report') + ' (Status: ' + xhr.status + ')');
      }
    };

    xhr.onerror = () => {
      this.showError(this.getI18nText('network_error', 'Network error occurred'));
    };

    xhr.send();
  }

  /**
   * Render a report's detail into the detail pane, fading out/in around the
   * content swap.
   * @param {object} data - Report fields: `id`, `health_report`, `created_at`, `user.name`, and optionally `formatted_html`.
   */
  renderReportDetail(data) {
    // Fade out
    this.detailContainer.style.opacity = '0';

    setTimeout(() => {
      // Format content using Markdown parser if available
      let formattedContent = data.formatted_html;
      if (typeof AiHelperMarkdownParser !== 'undefined') {
        const parser = new AiHelperMarkdownParser();
        formattedContent = parser.parse(data.health_report);
      }

      // Build HTML
      const html = this.buildDetailHTML(data, formattedContent);
      this.detailContainer.innerHTML = html;

      // Fade in
      setTimeout(() => {
        this.detailContainer.style.opacity = '1';
      }, 10);

      // Attach export event handlers
      this.attachExportEvents(data);
    }, 300);
  }

  /**
   * Build the detail pane's HTML for a report.
   * @param {object} data - Report fields (see `renderReportDetail`).
   * @param {string} formattedContent - The report body, already rendered from markdown to HTML.
   * @returns {string} HTML for the detail pane.
   */
  buildDetailHTML(data, formattedContent) {
    const createdAt = this.formatDateTime(data.created_at);
    const userName = this.escapeHtml(data.user.name);
    const reportId = data.id;
    const projectId = this.getProjectId();
    const exportLabel = this.getI18nText('label_export_to', 'Export to');
    const createdOnLabel = this.getI18nText('field_created_on', 'Created on');
    const authorLabel = this.getI18nText('field_author', 'Author');

    return `
      <div class="ai-helper-health-report-detail" data-report-id="${reportId}">

        <div class="ai-helper-health-report-meta">
          <p>
            <strong>${createdOnLabel}:</strong>
            ${createdAt}
          </p>
          <p>
            <strong>${authorLabel}:</strong>
            ${userName}
          </p>
        </div>

        <div class="ai-helper-project-health-content has-report">
          <div id="ai-helper-project-health-result" class="ai-helper-final-content">
            ${formattedContent}
          </div>
          <input type="hidden" id="ai-helper-health-report-content" value="${this.escapeHtml(data.health_report)}" />
        </div>

        <p class="other-formats">
          ${exportLabel}
          <span><a href="#" class="text" id="ai-helper-markdown-export-detail">Markdown</a></span>
          <span><a href="/projects/${projectId}/ai_helper/health_reports/${reportId}.pdf" class="pdf" id="ai-helper-pdf-export-detail">PDF</a></span>
        </p>
      </div>
    `;
  }

  /**
   * Show a loading spinner in the detail pane.
   */
  showLoading() {
    this.detailContainer.innerHTML = '<div class="ai-helper-loader"></div>';
  }

  /**
   * Show an error message in the detail pane.
   * @param {string} message - The error text to display.
   */
  showError(message) {
    this.detailContainer.innerHTML = `
      <div class="ai-helper-error">
        <p>${this.escapeHtml(message)}</p>
      </div>
    `;
  }

  /**
   * Confirm and delete a report via AJAX, removing its row and selecting
   * the next report if the deleted one was selected.
   * @param {HTMLElement} link - The clicked delete (`.icon-del`) link.
   */
  handleDelete(link) {
    const confirmMessage = link.dataset.confirm || this.getI18nText('text_are_you_sure', 'Are you sure?');
    if (!confirm(confirmMessage)) {
      return;
    }

    const url = link.href;
    const row = link.closest('.ai-helper-report-row');
    const reportId = row.dataset.reportId;

    const xhr = new XMLHttpRequest();
    xhr.open('DELETE', url, true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.setRequestHeader('Accept', 'application/json');

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    if (csrfToken) {
      xhr.setRequestHeader('X-CSRF-Token', csrfToken);
    }

    xhr.onload = () => {
      if (xhr.status === 200) {
        // Remove row
        row.remove();

        // If deleted report was selected, show next report
        if (this.selectedReportId === reportId) {
          this.selectNextReport();
        }
      } else {
        alert(this.getI18nText('error_deleting_report', 'Failed to delete report'));
      }
    };

    xhr.onerror = () => {
      alert(this.getI18nText('network_error', 'Network error occurred'));
    };

    xhr.send();
  }

  /**
   * Select the first remaining report row, or show the placeholder if none remain.
   */
  selectNextReport() {
    const rows = document.querySelectorAll('.ai-helper-report-row');
    if (rows.length > 0) {
      // Select first report
      this.selectReport(rows[0]);
    } else {
      // No reports left, show placeholder
      this.showPlaceholder();
    }
  }

  /**
   * Show the "select a report" placeholder and clear the current selection.
   */
  showPlaceholder() {
    const placeholderText = this.getI18nText('label_ai_helper_select_report_to_view',
                                             'Generate a report or select one from the history on the left');
    this.detailContainer.innerHTML = `
      <div class="ai-helper-detail-placeholder">
        <p>${placeholderText}</p>
      </div>
    `;
    this.selectedReportId = null;
  }

  /**
   * Bind the detail pane's markdown export link (PDF export needs no
   * handler; its href is already correct).
   * @param {object} data - Report fields (see `renderReportDetail`).
   */
  attachExportEvents(data) {
    const markdownExportLink = document.getElementById('ai-helper-markdown-export-detail');

    if (markdownExportLink) {
      markdownExportLink.addEventListener('click', (e) => {
        e.preventDefault();
        this.exportMarkdown(data.health_report);
      });
    }

    // PDF export link already has correct href, no additional handler needed
  }

  /**
   * Submit the report content to the markdown export endpoint via a
   * dynamically-built form POST (triggers a file download).
   * @param {string} content - The report's raw markdown content.
   */
  exportMarkdown(content) {
    // Create form to submit markdown export
    const form = document.createElement('form');
    form.method = 'POST';
    form.action = this.getMarkdownExportUrl();

    const contentField = document.createElement('input');
    contentField.type = 'hidden';
    contentField.name = 'health_report_content';
    contentField.value = content;

    const csrfField = document.createElement('input');
    csrfField.type = 'hidden';
    csrfField.name = 'authenticity_token';
    csrfField.value = document.querySelector('meta[name="csrf-token"]').getAttribute('content');

    form.appendChild(contentField);
    form.appendChild(csrfField);
    document.body.appendChild(form);
    form.submit();
    document.body.removeChild(form);
  }

  // Utility methods
  /**
   * Format an ISO date string using the browser's locale.
   * @param {string} dateString - An ISO 8601 date/time string.
   * @returns {string} The locale-formatted date/time.
   */
  formatDateTime(dateString) {
    const date = new Date(dateString);
    return date.toLocaleString();
  }

  /**
   * Escape HTML special characters to prevent XSS.
   * @param {string} text - The raw text to escape.
   * @returns {string} The HTML-escaped text.
   */
  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  /**
   * Extract the current project's identifier from the page URL.
   * @returns {string} The project id/identifier, or `''` if not found.
   */
  getProjectId() {
    // Extract project ID from URL
    const match = window.location.pathname.match(/\/projects\/([^/]+)/);
    return match ? match[1] : '';
  }

  /**
   * Build the markdown export endpoint URL for the current project.
   * @returns {string} The markdown export URL.
   */
  getMarkdownExportUrl() {
    const projectId = this.getProjectId();
    return `/projects/${projectId}/ai_helper/project_health_markdown`;
  }

  /**
   * Look up an internationalized string from its meta tag.
   * @param {string} key - The i18n key (meta tag is `i18n-<key>`).
   * @param {string} defaultText - Fallback text if the meta tag is absent.
   * @returns {string} The localized text, or `defaultText` if unavailable.
   */
  getI18nText(key, defaultText) {
    // Get internationalized text from meta tags if available
    const metaTag = document.querySelector(`meta[name="i18n-${key}"]`);
    return metaTag ? metaTag.getAttribute('content') : defaultText;
  }
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
  new AiHelperMasterDetail();
});

// Global function to update health report history after generation
window.updateHealthReportHistory = function(callback) {
  // Reload health report history
  const historyContainer = document.getElementById('ai-helper-health-report-history-container');
  if (!historyContainer) {return;}

  const match = window.location.pathname.match(/\/projects\/([^/]+)/);
  if (!match) {return;}
  const projectId = match[1];
  const url = `/projects/${projectId}/ai_helper/health_reports`;

  const xhr = new XMLHttpRequest();
  xhr.open('GET', url, true);
  xhr.setRequestHeader('Accept', 'text/html');

  xhr.onload = function() {
    if (xhr.status === 200) {
      historyContainer.innerHTML = xhr.responseText;
      // Re-initialize master-detail after updating history
      const masterDetail = new AiHelperMasterDetail();

      if (typeof callback === 'function') {
        callback(masterDetail);
      } else {
        // Auto-select and display the first report (most recent)
        setTimeout(() => {
          const firstReportRow = document.querySelector('.ai-helper-report-row');
          if (firstReportRow && masterDetail) {
            masterDetail.selectedReportId = null;
            masterDetail.selectReport(firstReportRow);
          }
        }, 100);
      }
    }
  };

  xhr.send();
};

// Store class in global scope
window.AiHelperMasterDetail = AiHelperMasterDetail;

/**
 * Enable the compare-reports button only when two different reports are selected.
 */
function updateComparisonButton() {
  const oldRadio = document.querySelector('.old-radio:checked');
  const newRadio = document.querySelector('.new-radio:checked');
  const compareButton = document.getElementById('compare-reports-button');

  if (!compareButton) {return;}

  if (oldRadio && newRadio && oldRadio.value !== newRadio.value) {
    compareButton.disabled = false;
  } else {
    compareButton.disabled = true;
  }
}

// Initialize comparison button state on page load
document.addEventListener('DOMContentLoaded', function() {
  updateComparisonButton();
});

// Make function globally available
window.updateComparisonButton = updateComparisonButton;

} // End guard against multiple script loading
