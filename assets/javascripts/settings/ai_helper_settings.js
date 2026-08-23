/**
 * AI Helper settings page: tab switching, model profile AJAX loading, and
 * conditional field visibility.
 * Extracted from ai_helper_settings/index.html.erb.
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
 * @param {HTMLElement} element
 * @param {string} html
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
 * @param {number|string} id
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

function setModelProfile() {
  const select = document.getElementById('ai_helper_setting_model_profile_id');
  const selectedId = select.value;
  if (selectedId) {
    loadModelProfile(selectedId);
  } else {
    document.getElementById('ai_helper_model_profile_description').innerHTML = '';
  }
}

function setThinkModelVisible() {
  const thinkEnabled = document.getElementById('ai_helper_setting_use_think_model').checked;
  const settingsDiv = document.getElementById('ai-helper-think-model-settings');
  settingsDiv.style.display = thinkEnabled ? '' : 'none';
}

function setAttachmentSettingsVisible() {
  const attachmentEnabled = document.getElementById('ai_helper_setting_attachment_send_enabled').checked;
  const settingsDiv = document.getElementById('ai-helper-attachment-settings');
  settingsDiv.style.display = attachmentEnabled ? '' : 'none';
}

function setVectorSearchVisible() {
  const vectorSearchEnabled = document.getElementById('ai_helper_setting_vector_search_enabled').checked;
  const vectorSearchDiv = document.getElementById('ai-helper-vector-search');
  vectorSearchDiv.style.display = vectorSearchEnabled ? '' : 'none';
  setVectorModelProfileToggleVisible();
}

function setVectorTargetProjectsVisible() {
  const registerAll = document.getElementById('ai_helper_setting_vector_register_all_projects');
  const container = document.getElementById('ai-helper-vector-target-projects');
  if (!registerAll || !container) {return;}
  container.style.display = registerAll.checked ? 'none' : '';
}

function setVectorModelProfileVisible() {
  const enabled = document.getElementById('ai_helper_setting_use_vector_model_profile').checked;
  const settingsDiv = document.getElementById('ai-helper-vector-model-profile-settings');
  settingsDiv.style.display = enabled ? '' : 'none';
}

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
}
window.initAiHelperSettingsPage = initAiHelperSettingsPage;
