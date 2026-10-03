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
    // Incremented per detail request so slower, superseded responses are dropped
    this.detailRequestId = 0;
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
   * Select a report row and fetch its server-rendered detail pane.
   * @param {HTMLElement} row - The `.ai-helper-report-row` element clicked.
   */
  selectReport(row) {
    const reportId = row.dataset.reportId;

    if (this.selectedReportId === reportId) {
      return; // Already selected
    }

    // Update selection state
    this.updateSelection(row, reportId);

    // Fetch the detail pane rendered by the server
    this.loadReportDetail(row.dataset.reportDetailUrl);
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
   * Fetch a report's detail pane HTML (server-rendered partial) via AJAX.
   * A response (or error) is ignored once a newer detail request has started,
   * so a slow earlier request cannot overwrite the currently selected report.
   * @param {string} url - The report detail endpoint.
   * @returns {Promise<void>} Resolves when the detail pane has been rendered,
   *   the error message has been shown, or the response was discarded as stale.
   */
  loadReportDetail(url) {
    const requestId = ++this.detailRequestId;
    const isStale = () => requestId !== this.detailRequestId;

    // Show loading state
    this.showLoading();

    return fetch(url, {
      headers: {
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'text/html'
      }
    })
      .then(response => {
        if (!response.ok) {
          throw new Error('HTTP status: ' + response.status);
        }
        return response.text();
      })
      .then(html => {
        if (isStale()) {
          return;
        }
        this.renderReportDetail(html);
      })
      .catch(error => {
        if (isStale()) {
          return;
        }
        console.error('Failed to load report detail:', error);
        // fetch() rejects with a TypeError on network failures
        const message = error instanceof TypeError
          ? this.getI18nText('network_error', 'Network error occurred')
          : this.getI18nText('error_loading_report', 'Failed to load report');
        this.showError(message);
      });
  }

  /**
   * Render a report's server-rendered detail HTML into the detail pane,
   * fading out/in around the content swap.
   * @param {string} html - The detail pane HTML from the server.
   */
  renderReportDetail(html) {
    const requestId = this.detailRequestId;

    // Fade out
    this.detailContainer.style.opacity = '0';

    setTimeout(() => {
      // Another report was selected during the fade; its request owns the pane now
      if (requestId !== this.detailRequestId) {
        return;
      }
      this.detailContainer.innerHTML = html;

      // Fade in
      setTimeout(() => {
        this.detailContainer.style.opacity = '1';
      }, 10);
    }, 300);
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

  // Utility methods
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
