// Master-Detail Layout Management for Health Report History
// Handles report selection, Ajax loading, and dynamic interactions

class AiHelperMasterDetail {
  constructor() {
    this.selectedReportId = null;
    this.masterPane = null;
    this.detailPane = null;
    this.detailContainer = null;
    this.init();
  }

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

  checkElements() {
    const layout = document.querySelector('.ai-helper-master-detail-layout');
    return layout !== null;
  }

  attachEventListeners() {
    // Show button click events
    const showLinks = document.querySelectorAll('.ai-helper-show-report');
    showLinks.forEach(link => {
      link.addEventListener('click', (e) => {
        e.preventDefault();
        const row = link.closest('.ai-helper-report-row');
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

  initializeSelection() {
    // Initialize with already selected report if any
    const selectedRow = document.querySelector('.ai-helper-report-row.selected');
    if (selectedRow) {
      this.selectedReportId = selectedRow.dataset.reportId;
    }
  }

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

  updateSelection(row, reportId) {
    // Remove selection from all rows
    document.querySelectorAll('.ai-helper-report-row').forEach(r => {
      r.classList.remove('selected');
    });

    // Add selection to clicked row
    row.classList.add('selected');
    this.selectedReportId = reportId;
  }

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

  buildDetailHTML(data, formattedContent) {
    const createdAt = this.formatDateTime(data.created_at);
    const userName = this.escapeHtml(data.user.name);
    const reportId = data.id;
    const projectId = this.getProjectId();
    const exportLabel = this.getI18nText('label_export_to', 'Export to');
    const reportDetailLabel = this.getI18nText('label_ai_helper_health_report_detail', 'Report Detail');
    const createdOnLabel = this.getI18nText('field_created_on', 'Created on');
    const authorLabel = this.getI18nText('field_author', 'Author');

    return `
      <div class="ai-helper-health-report-detail" data-report-id="${reportId}">
        <div class="contextual">
          <a href="#" class="icon icon-text" id="ai-helper-markdown-export-detail">
            ${exportLabel} Markdown
          </a>
          <a href="/projects/${projectId}/ai_helper/health_reports/${reportId}.pdf" class="icon icon-pdf" id="ai-helper-pdf-export-detail">
            ${exportLabel} PDF
          </a>
        </div>

        <h3>
          <span class="icon-svg icon-ai-helper-robot"></span>
          ${reportDetailLabel}
        </h3>

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

        <div class="ai-helper-project-health-content">
          <div id="ai-helper-project-health-result" class="ai-helper-final-content">
            ${formattedContent}
          </div>
          <input type="hidden" id="ai-helper-health-report-content" value="${this.escapeHtml(data.health_report)}" />
        </div>
      </div>
    `;
  }

  showLoading() {
    this.detailContainer.innerHTML = '<div class="ai-helper-loader"></div>';
  }

  showError(message) {
    this.detailContainer.innerHTML = `
      <div class="ai-helper-error">
        <p>${this.escapeHtml(message)}</p>
      </div>
    `;
  }

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

  attachExportEvents(data) {
    const markdownExportLink = document.getElementById('ai-helper-markdown-export-detail');
    const pdfExportLink = document.getElementById('ai-helper-pdf-export-detail');

    if (markdownExportLink) {
      markdownExportLink.addEventListener('click', (e) => {
        e.preventDefault();
        this.exportMarkdown(data.health_report);
      });
    }

    // PDF export link already has correct href, no additional handler needed
  }

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
  formatDateTime(dateString) {
    const date = new Date(dateString);
    return date.toLocaleString();
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  getProjectId() {
    // Extract project ID from URL
    const match = window.location.pathname.match(/\/projects\/([^\/]+)/);
    return match ? match[1] : '';
  }

  getMarkdownExportUrl() {
    const projectId = this.getProjectId();
    return `/projects/${projectId}/ai_helper/project_health_markdown`;
  }

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
window.updateHealthReportHistory = function() {
  // Reload health report history
  const historyContainer = document.getElementById('ai-helper-health-report-history-container');
  if (!historyContainer) return;

  const projectId = window.location.pathname.match(/\/projects\/([^\/]+)/)[1];
  const url = `/projects/${projectId}/ai_helper/health_reports`;

  const xhr = new XMLHttpRequest();
  xhr.open('GET', url, true);
  xhr.setRequestHeader('Accept', 'text/html');

  xhr.onload = function() {
    if (xhr.status === 200) {
      historyContainer.innerHTML = xhr.responseText;
      // Re-initialize master-detail after updating history
      new AiHelperMasterDetail();
    }
  };

  xhr.send();
};
