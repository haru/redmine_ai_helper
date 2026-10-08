/**
 * AI Helper settings page: tab switching, model profile AJAX loading, and
 * conditional field visibility.
 * Extracted from ai_helper_settings/index.html.erb.
 */

/**
 * Read the settings page's configuration JSON from its container element.
 * @returns {object} Parsed config (model profile/vector-search options, labels, etc.), or `{}` if absent.
 */
function getAiHelperSettingsConfig() {
  const container = document.getElementById('ai-helper-settings-index');
  return container ? JSON.parse(container.dataset.config || '{}') : {};
}

/**
 * Set an element's HTML and execute any `<script>` tags it contains.
 * Plain `element.innerHTML = html` does not execute embedded scripts; this
 * settings page can't rely on the shared `ai_helper` global's equivalent
 * helper, since `ai_helper.js` is only loaded on pages with a project (via
 * `_html_header.html.erb`) and this admin page has none.
 * @param {HTMLElement} element - The element to fill.
 * @param {string} html - HTML string, server-rendered from ERB templates.
 */
function setHtmlAndRunScripts(element, html) {
  element.innerHTML = html;
  element.querySelectorAll('script').forEach(function(script) {
    const newScript = document.createElement('script');
    newScript.textContent = script.textContent;
    document.body.appendChild(newScript);
  });
}

/**
 * Load a model profile's detail view via AJAX into the description area.
 * Uses `setHtmlAndRunScripts` (not plain innerHTML) because the loaded
 * partial ends in a bridge `<script>` that must execute on each load.
 * @param {number|string} id - The model profile's ID.
 */
function loadModelProfile(id) {
  const config = getAiHelperSettingsConfig();
  const descriptionDiv = document.getElementById('ai_helper_model_profile_description');

  fetch(config.modelProfilesPath + '/' + id)
    .then(function(response) {
      if (!response.ok) {throw new Error('HTTP ' + response.status);}
      return response.text();
    })
    .then(function(html) {
      setHtmlAndRunScripts(descriptionDiv, html);
      modelTypeChanged();
    })
    .catch(function() {
      descriptionDiv.textContent = config.loadErrorMessage;
    });
}

/**
 * Load the selected model profile's detail view, or clear it when none is selected.
 */
function setModelProfile() {
  const select = document.getElementById('ai_helper_setting_model_profile_id');
  const selectedId = select.value;
  if (selectedId) {
    loadModelProfile(selectedId);
  } else {
    document.getElementById('ai_helper_model_profile_description').innerHTML = '';
  }
}

/**
 * Show or hide the "think model" settings section based on its checkbox.
 */
function setThinkModelVisible() {
  const thinkEnabled = document.getElementById('ai_helper_setting_use_think_model').checked;
  const settingsDiv = document.getElementById('ai-helper-think-model-settings');
  settingsDiv.style.display = thinkEnabled ? '' : 'none';
}

/**
 * Show or hide the attachment-sending settings section based on its checkbox.
 */
function setAttachmentSettingsVisible() {
  const attachmentEnabled = document.getElementById('ai_helper_setting_attachment_send_enabled').checked;
  const settingsDiv = document.getElementById('ai-helper-attachment-settings');
  settingsDiv.style.display = attachmentEnabled ? '' : 'none';
}

/**
 * Show or hide the vector-search settings section based on its checkbox,
 * and sync the dependent vector-model-profile toggle's visibility.
 */
function setVectorSearchVisible() {
  const vectorSearchEnabled = document.getElementById('ai_helper_setting_vector_search_enabled').checked;
  const vectorSearchDiv = document.getElementById('ai-helper-vector-search');
  vectorSearchDiv.style.display = vectorSearchEnabled ? '' : 'none';
  setVectorModelProfileToggleVisible();
}

/**
 * Hide the target-projects picker when "register all projects" is checked.
 */
function setVectorTargetProjectsVisible() {
  const registerAll = document.getElementById('ai_helper_setting_vector_register_all_projects');
  const container = document.getElementById('ai-helper-vector-target-projects');
  if (!registerAll || !container) {return;}
  container.style.display = registerAll.checked ? 'none' : '';
}

/**
 * Show or hide the vector-search model profile settings based on its checkbox.
 */
function setVectorModelProfileVisible() {
  const enabled = document.getElementById('ai_helper_setting_use_vector_model_profile').checked;
  const settingsDiv = document.getElementById('ai-helper-vector-model-profile-settings');
  settingsDiv.style.display = enabled ? '' : 'none';
}

/**
 * Show the "use a dedicated vector model profile" row only while vector
 * search is enabled, and sync its dependent settings section.
 */
function setVectorModelProfileToggleVisible() {
  const vectorSearchEnabled = document.getElementById('ai_helper_setting_vector_search_enabled').checked;
  const toggleRow = document.getElementById('ai_helper_setting_use_vector_model_profile');
  if (toggleRow) {
    const parentP = toggleRow.closest('p');
    if (parentP) {
      parentP.style.display = vectorSearchEnabled ? '' : 'none';
    }
    if (!vectorSearchEnabled) {
      const settingsDiv = document.getElementById('ai-helper-vector-model-profile-settings');
      if (settingsDiv) {settingsDiv.style.display = 'none';}
    } else {
      setVectorModelProfileVisible();
    }
  }
}

/**
 * Show the "send user ID" row only when the currently loaded model type
 * supports it.
 */
function setSendUserIdVisible() {
  const config = getAiHelperSettingsConfig();
  // ai_helper_model_type only exists once the model tab's profile detail is
  // loaded; absent on other tabs (jQuery's `.text()` used to no-op here).
  const modelType = document.getElementById('ai_helper_model_type')?.textContent || '';
  const supported = modelType !== '' && config.userIdSupportedTypes.includes(modelType);
  const sendUserIdDiv = document.getElementById('ai-helper-send-user-id');
  if (sendUserIdDiv) {sendUserIdDiv.style.display = supported ? '' : 'none';}
}
window.setSendUserIdVisible = setSendUserIdVisible;

/**
 * Show/hide the model-type-specific fields (dimension, embedding URL) for
 * the just-loaded model profile, and refresh the "send user ID" visibility.
 */
function modelTypeChanged() {
  const config = getAiHelperSettingsConfig();
  const modelType = document.getElementById('ai_helper_model_type')?.textContent || '';
  const dimensionDiv = document.getElementById('ai_helper_dimension');
  const embeddingUrlDiv = document.getElementById('ai_helper_embedding_url');
  if (dimensionDiv) {dimensionDiv.style.display = modelType === config.compatibleType ? '' : 'none';}
  if (embeddingUrlDiv) {embeddingUrlDiv.style.display = modelType === config.azureType ? '' : 'none';}
  setSendUserIdVisible();
}
window.modelTypeChanged = modelTypeChanged;

/**
 * Build FormData with an `ai_helper_setting[key]` entry for each value.
 * @param {{[key: string]: string}} values Setting values keyed by attribute name.
 * @returns {FormData} Form data ready to post.
 */
function settingFormData(values) {
  const formData = new FormData();
  Object.keys(values).forEach(function(key) {
    formData.append('ai_helper_setting[' + key + ']', values[key]);
  });
  return formData;
}

/**
 * Wire up a "test connection" button (shared by the Qdrant and embedding tests).
 * Posts the current (unsaved) form values, shows progress while running, and
 * discards results that are stale because an input changed or a newer request
 * started. Results are rendered with textContent only.
 * @param {object} options Binding options.
 * @param {HTMLButtonElement} options.button Button that starts the test.
 * @param {HTMLElement} options.result Element that shows the result message.
 * @param {HTMLElement[]} options.fields Inputs whose input/change events clear the result and make a running request stale.
 * @param {function(): FormData} options.buildFormData Returns the form data to post.
 * @param {object} options.config Parsed data-config with testConnectionUrl, testConnectionSuccessLabel, testConnectionFailedLabel and loadingLabel.
 * @param {function(object): string} [options.formatSuccess] Returns the success message for the response data; defaults to testConnectionSuccessLabel.
 */
function bindConnectionTest({ button, result, fields, buildFormData, config, formatSuccess }) {
  const successText = formatSuccess || function() { return config.testConnectionSuccessLabel; };
  let requestSeq = 0;

  /** Empty the result area and drop its status class. */
  function clearResult() {
    result.textContent = '';
    result.className = '';
  }

  /**
   * Show a result message.
   * @param {boolean} success Whether the test succeeded.
   * @param {string} text Message shown via textContent.
   */
  function showResult(success, text) {
    result.textContent = text;
    result.className = success ? 'ai-helper-connection-success' : 'ai-helper-connection-failure';
  }

  button.addEventListener('click', function() {
    const seq = ++requestSeq;
    const body = buildFormData();

    button.disabled = true;
    result.textContent = config.loadingLabel;
    result.className = '';

    fetch(config.testConnectionUrl, {
      method: 'POST',
      headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content },
      body: body
    })
      .then(function(response) {
        // Non-JSON bodies (e.g. a login page after the session expired or a
        // CSRF error page) carry no message, so report the HTTP status instead.
        return response.json().catch(function() {
          return { success: false, error: 'HTTP ' + response.status };
        });
      })
      .then(function(data) {
        if (seq !== requestSeq) { return; }
        if (data.success) {
          showResult(true, successText(data));
        } else {
          showResult(false, config.testConnectionFailedLabel + (data.error ? ': ' + data.error : ''));
        }
      })
      .catch(function(error) {
        if (seq !== requestSeq) { return; }
        showResult(false, config.testConnectionFailedLabel + ': ' + error.message);
      })
      .finally(function() {
        button.disabled = false;
      });
  });

  fields.forEach(function(field) {
    ['input', 'change'].forEach(function(type) {
      field.addEventListener(type, function() {
        requestSeq++;
        clearResult();
      });
    });
  });
}

/**
 * Wire up the Qdrant "test connection" button in the vector search tab.
 * Sends the current (unsaved) URI and API key to the server. Does nothing
 * when the section is absent.
 */
function initVectorConnectionTest() {
  const container = document.getElementById('ai-helper-qdrant-connection');
  if (!container) { return; }
  const config = JSON.parse(container.dataset.config || '{}');
  const button = document.getElementById('ai-helper-vector-test-connection-btn');
  const result = document.getElementById('ai-helper-vector-test-connection-result');
  const uriField = document.getElementById('ai_helper_setting_vector_search_uri');
  const keyField = document.getElementById('ai_helper_setting_vector_search_api_key');
  if (!button || !result || !uriField || !keyField) { return; }

  bindConnectionTest({
    button,
    result,
    config,
    fields: [uriField, keyField],
    buildFormData: function() {
      return settingFormData({
        vector_search_uri: uriField.value,
        vector_search_api_key: keyField.value
      });
    }
  });
}
window.initVectorConnectionTest = initVectorConnectionTest;

/**
 * Wire up the embedding model "test connection" button in the vector search
 * tab. Sends the current (unsaved) model profile selections and embedding
 * model name, and shows the vector dimension on success. Does nothing when
 * the section is absent.
 */
function initEmbeddingConnectionTest() {
  const container = document.getElementById('ai-helper-embedding-connection');
  if (!container) { return; }
  const config = JSON.parse(container.dataset.config || '{}');
  const button = document.getElementById('ai-helper-embedding-test-connection-btn');
  const result = document.getElementById('ai-helper-embedding-test-connection-result');
  const modelProfileField = document.getElementById('ai_helper_setting_model_profile_id');
  const useVectorProfileField = document.getElementById('ai_helper_setting_use_vector_model_profile');
  const vectorProfileField = document.getElementById('ai_helper_setting_vector_model_profile_id');
  const embeddingModelField = document.getElementById('ai_helper_setting_embedding_model');
  if (!button || !result || !modelProfileField || !useVectorProfileField || !vectorProfileField || !embeddingModelField) { return; }

  bindConnectionTest({
    button,
    result,
    config,
    fields: [modelProfileField, useVectorProfileField, vectorProfileField, embeddingModelField],
    buildFormData: function() {
      return settingFormData({
        model_profile_id: modelProfileField.value,
        use_vector_model_profile: useVectorProfileField.checked ? '1' : '0',
        vector_model_profile_id: vectorProfileField.value,
        embedding_model: embeddingModelField.value
      });
    },
    formatSuccess: function(data) {
      return config.testConnectionSuccessLabel + ' (' + config.dimensionLabel + ': ' + data.dimension + ')';
    }
  });
}
window.initEmbeddingConnectionTest = initEmbeddingConnectionTest;

/**
 * Wire up the settings page: tab-hidden-field sync, event bindings, and
 * initial visibility state. Called once via a bridge `<script>` at the same
 * position the original inline script occupied (after the form, so the
 * elements it queries already exist), since this file itself is now loaded
 * ahead of time from `<head>`.
 */
function initAiHelperSettingsPage() {
  const tabHidden = document.querySelector('input[name="tab"]');
  const tabLinks = document.querySelectorAll('.tabs a[id^="tab-"]');
  tabLinks.forEach(function(link) {
    link.addEventListener('click', function() {
      const name = this.id.replace('tab-', '');
      if (tabHidden) { tabHidden.value = name; }
    });
  });

  document.getElementById('ai_helper_setting_model_profile_id').addEventListener('change', function() {
    setModelProfile();
  });
  document.getElementById('ai_helper_setting_use_think_model').addEventListener('change', function() {
    setThinkModelVisible();
  });
  document.getElementById('ai_helper_setting_attachment_send_enabled').addEventListener('change', function() {
    setAttachmentSettingsVisible();
  });
  document.getElementById('ai_helper_setting_vector_search_enabled').addEventListener('change', function() {
    setVectorSearchVisible();
  });
  document.getElementById('ai_helper_setting_vector_register_all_projects').addEventListener('change', function() {
    setVectorTargetProjectsVisible();
  });
  document.getElementById('ai_helper_setting_use_vector_model_profile').addEventListener('change', function() {
    setVectorModelProfileVisible();
  });

  setModelProfile();
  setThinkModelVisible();
  setAttachmentSettingsVisible();
  setVectorSearchVisible();
  setVectorTargetProjectsVisible();
  setSendUserIdVisible();
  initVectorConnectionTest();
  initEmbeddingConnectionTest();
}
window.initAiHelperSettingsPage = initAiHelperSettingsPage;
