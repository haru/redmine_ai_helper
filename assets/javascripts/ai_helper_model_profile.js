/**
 * Model profile detail (copy dialog) and form (LLM-type-driven field
 * visibility, autofill prevention, connection test).
 * Extracted from ai_helper_model_profiles/_show.html.erb and _form.html.erb.
 */
const AiHelperModelProfile = (() => {
  /**
   * Wire up the "copy this profile" dialog on the model profile detail
   * view. Called fresh each time the detail view is (re-)loaded via AJAX
   * into the settings page's model tab.
   */
  function initShow() {
    const dialog = document.getElementById('copy-profile-dialog');
    if (!dialog) return;
    const config = JSON.parse(dialog.dataset.config || '{}');

    const copyBtn = document.getElementById('copy-model-profile-btn');
    const nameInput = document.getElementById('new-profile-name');
    const submitBtn = document.getElementById('copy-profile-submit');
    const cancelBtn = document.getElementById('copy-profile-cancel');
    const errorEl = document.getElementById('copy-profile-error');
    const csrfToken = document.querySelector('meta[name="csrf-token"]').content;

    copyBtn.addEventListener('click', function(e) {
      e.preventDefault();
      nameInput.value = '';
      errorEl.style.display = 'none';
      dialog.showModal();
      nameInput.focus();
    });

    nameInput.addEventListener('keydown', function(e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        submitBtn.click();
      }
    });

    cancelBtn.addEventListener('click', function(e) {
      e.preventDefault();
      dialog.close();
    });

    submitBtn.addEventListener('click', function() {
      errorEl.style.display = 'none';
      const name = nameInput.value.trim();

      fetch(config.copyUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-CSRF-Token': csrfToken
        },
        body: 'name=' + encodeURIComponent(name)
      })
        .then(function(response) {
          const contentType = response.headers.get('Content-Type') || '';
          if (contentType.includes('application/json')) {
            return response.json();
          }
          return response.text().then(function() {
            throw new Error(response.statusText || 'Server error');
          });
        })
        .then(function(data) {
          if (data.success) {
            window.location.href = config.redirectUrl;
          } else {
            errorEl.textContent = data.errors.join(', ');
            errorEl.style.display = 'block';
          }
        })
        .catch(function(error) {
          errorEl.textContent = error.message;
          errorEl.style.display = 'block';
        });
    });
  }

  /**
   * Wire up the model profile form: LLM-type-driven field visibility,
   * autofill-prevention on sensitive fields, and the connection test button.
   */
  function initForm() {
    const configContainer = document.getElementById('ai-helper-model-profile-form');
    if (!configContainer) return;
    const config = JSON.parse(configContainer.dataset.config || '{}');

    const llmTypeSelect = document.getElementById('ai_helper_model_profile_llm_type');

    /**
     * @param {string} selectValue - Selected `llm_type` value.
     * @returns {boolean} Whether the base URI field is required for this LLM type.
     */
    function isBaseUriRequired(selectValue) {
      return selectValue === config.compatibleType || selectValue === config.azureType;
    }

    /**
     * @param {HTMLElement|null} element
     * @param {boolean} visible
     */
    function setVisible(element, visible) {
      if (element) element.style.display = visible ? 'block' : 'none';
    }

    /**
     * Show/hide the base URI, access key requirement, and organization ID
     * fields based on the currently selected LLM type.
     */
    function handleLlmTypeChange() {
      const selectedValue = llmTypeSelect.value;
      const baseUriElement = document.getElementById('ai-helper-model-base-uri');
      const accessKeyRequiredElement = document.querySelector('#ai-helper-mode-access-key .required');
      const organizationIdElement = document.getElementById('ai-helper-model-organization-id');

      setVisible(baseUriElement, isBaseUriRequired(selectedValue));
      setVisible(accessKeyRequiredElement, selectedValue !== config.compatibleType);
      setVisible(organizationIdElement, selectedValue === config.openaiType);
    }

    if (llmTypeSelect) {
      llmTypeSelect.addEventListener('change', handleLlmTypeChange);
      // Trigger change event on page load
      handleLlmTypeChange();
    }

    // Prevent browser autofill from injecting saved credentials into sensitive fields.
    // Fields are rendered readonly so the browser skips them; readonly is removed on user interaction.
    ['ai_helper_model_profile_organization_id', 'ai_helper_model_profile_access_key'].forEach(function(id) {
      const input = document.getElementById(id);
      if (input) {
        const clearReadonly = function() { input.removeAttribute('readonly'); };
        input.addEventListener('focus', clearReadonly);
        input.addEventListener('mousedown', clearReadonly);
      }
    });

    // Connection test button
    const testConnectionBtn = document.getElementById('ai-helper-test-connection-btn');
    const testConnectionResult = document.getElementById('ai-helper-test-connection-result');

    if (testConnectionBtn) {
      testConnectionBtn.addEventListener('click', function(event) {
        event.preventDefault();
        if (testConnectionBtn.dataset.loading) return;
        testConnectionBtn.dataset.loading = 'true';
        testConnectionBtn.disabled = true;
        testConnectionResult.textContent = '';
        testConnectionResult.className = '';

        const form = testConnectionBtn.closest('form');
        const formData = new FormData(form);
        const idField = document.getElementById('id');
        if (idField) {
          formData.set('id', idField.value);
        }

        fetch(config.testConnectionUrl, {
          method: 'POST',
          headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content },
          body: formData
        })
          .then(function(response) {
            const contentType = response.headers.get('Content-Type') || '';
            if (!contentType.includes('application/json')) {
              return response.text().then(function() {
                return { success: false, error: config.testConnectionFailedLabel };
              });
            }
            return response.json();
          })
          .then(function(data) {
            if (data.success) {
              testConnectionResult.textContent = config.testConnectionSuccessLabel;
              testConnectionResult.className = 'ai-helper-connection-success';
            } else {
              testConnectionResult.textContent = config.testConnectionFailedLabel + (data.error ? ': ' + data.error : '');
              testConnectionResult.className = 'ai-helper-connection-failure';
            }
          })
          .catch(function(error) {
            testConnectionResult.textContent = config.testConnectionFailedLabel + ': ' + error.message;
            testConnectionResult.className = 'ai-helper-connection-failure';
          })
          .finally(function() {
            delete testConnectionBtn.dataset.loading;
            testConnectionBtn.disabled = false;
          });
      });

      // Auto-clear result when any form field changes
      const form = testConnectionBtn.closest('form');
      if (form) {
        form.querySelectorAll('input, select, textarea').forEach(function(field) {
          field.addEventListener('input', function() { testConnectionResult.textContent = ''; });
          field.addEventListener('change', function() { testConnectionResult.textContent = ''; });
        });
      }
    }
  }

  return { initShow, initForm };
})();

window.AiHelperModelProfile = AiHelperModelProfile;

document.addEventListener('DOMContentLoaded', function() {
  AiHelperModelProfile.initForm();
});
