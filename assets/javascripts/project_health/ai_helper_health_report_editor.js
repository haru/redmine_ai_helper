// Inline editor for stored project health reports.
// Uses event delegation on document so it keeps working after the detail pane is replaced.
(function () {
  if (window.aiHelperHealthReportEditorLoaded) {
    return;
  }
  window.aiHelperHealthReportEditorLoaded = true;

  // Find the root element of the report body containing the given node.
  const bodyOf = function (node) {
    return node.closest('.ai-helper-health-report-body');
  };

  // Show the edit form, building the Markdown toolbar on first use.
  const startEdit = function (link) {
    const body = bodyOf(link);
    const form = body.querySelector('.ai-helper-health-report-edit-form');
    const textarea = form.querySelector('textarea');
    body.querySelector('.ai-helper-health-report-view').hidden = true;
    link.hidden = true;
    form.hidden = false;
    if (!form.dataset.toolbarReady && typeof window.jsToolBar === 'function') {
      const toolbar = new window.jsToolBar(textarea);
      toolbar.setHelpLink(textarea.dataset.helpUrl);
      toolbar.setPreviewUrl(textarea.dataset.previewUrl);
      toolbar.draw();
      form.dataset.toolbarReady = 'true';
    }
    textarea.focus();
  };

  // Discard changes and go back to the read-only view.
  const cancelEdit = function (cancelLink) {
    const body = bodyOf(cancelLink);
    const form = cancelLink.closest('form');
    form.querySelector('textarea').value = form.querySelector('textarea').defaultValue;
    form.querySelector('.ai-helper-health-report-edit-errors').hidden = true;
    form.hidden = true;
    body.querySelector('.ai-helper-health-report-view').hidden = false;
    const editLink = body.querySelector('.ai-helper-health-report-edit-link');
    if (editLink) {
      editLink.hidden = false;
    }
  };

  // Switch between the edited content and the preserved AI-generated original.
  const toggleOriginal = function (link) {
    const body = bodyOf(link);
    const showOriginal = link.classList.contains('ai-helper-health-report-show-original');
    body.querySelector('.ai-helper-health-report-current').hidden = showOriginal;
    body.querySelector('.ai-helper-health-report-original').hidden = !showOriginal;
    body.querySelector('.ai-helper-health-report-show-original').hidden = showOriginal;
    body.querySelector('.ai-helper-health-report-show-current').hidden = !showOriginal;
  };

  // Show server-side errors without replacing the form so the input is preserved.
  const showErrors = function (form, errors) {
    const box = form.querySelector('.ai-helper-health-report-edit-errors');
    box.textContent = '';
    const list = document.createElement('ul');
    errors.forEach(function (message) {
      const item = document.createElement('li');
      item.textContent = message;
      list.appendChild(item);
    });
    box.appendChild(list);
    box.hidden = false;
  };

  // Submit the edit via fetch and swap in the re-rendered report on success.
  const submitEdit = function (form) {
    const body = bodyOf(form);
    const csrf = document.querySelector('meta[name="csrf-token"]');
    fetch(body.dataset.updateUrl, {
      method: 'PATCH',
      body: new FormData(form),
      headers: {
        'X-CSRF-Token': csrf ? csrf.content : '',
        'Accept': 'application/json'
      }
    }).then(function (response) {
      return response.json().then(function (json) {
        return { ok: response.ok, status: response.status, json: json };
      });
    }).then(function (result) {
      if (result.ok) {
        const reportId = body.dataset.reportId;
        body.outerHTML = result.json.html;
        if (result.json.edited) {
          const marker = document.querySelector('tr[data-report-id="' + reportId + '"] .ai-helper-health-report-edited-marker');
          if (marker) {
            marker.hidden = false;
          }
        }
      } else {
        // A 409 means the stored lock_version is stale; every retry would conflict again,
        // so keep the typed text visible and ask the user to reload.
        const errors = result.json.errors || [];
        showErrors(form, result.status === 409 ? errors.concat([form.dataset.conflictHint || 'Reload the page to get the latest version; your text is kept in the editor.']) : errors);
      }
    }).catch(function (error) {
      showErrors(form, [error.message]);
    });
  };

  document.addEventListener('click', function (event) {
    const editLink = event.target.closest('.ai-helper-health-report-edit-link');
    if (editLink) {
      event.preventDefault();
      startEdit(editLink);
      return;
    }
    const toggleLink = event.target.closest('.ai-helper-health-report-show-original, .ai-helper-health-report-show-current');
    if (toggleLink) {
      event.preventDefault();
      toggleOriginal(toggleLink);
      return;
    }
    const cancelLink = event.target.closest('.ai-helper-health-report-edit-cancel');
    if (cancelLink) {
      event.preventDefault();
      cancelEdit(cancelLink);
    }
  });

  document.addEventListener('submit', function (event) {
    const form = event.target.closest('.ai-helper-health-report-edit-form');
    if (form) {
      event.preventDefault();
      submitEdit(form);
    }
  });
})();
