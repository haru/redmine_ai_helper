/**
 * Wiki auto-completion and typo checker initialization.
 * Extracted from wiki/_textarea_overlay.html.erb.
 */

/**
 * Wire up auto-completion for the wiki content textarea and reposition its checkbox.
 */
function initializeWikiCompletion() {
  if (window.aiHelperWikiCompletionInitialized) {
    return;
  }

  const container = document.getElementById('ai-helper-wiki-textarea-overlay');
  if (!container) return;
  const config = JSON.parse(container.dataset.config || '{}');

  const wikiTextarea = document.getElementById('content_text');

  if (wikiTextarea && typeof AiHelperAutoCompletion !== 'undefined') {
    const pageMatch = window.location.pathname.match(/\/wiki\/([^/]+)/);
    let endpoint = config.endpoint;
    if (pageMatch) {
      const pageName = pageMatch[1].replace(/\/.edit.*$/, '');
      endpoint = '/projects/' + config.projectIdentifier + '/ai_helper/wiki/' + pageName + '/suggest_completion';
    }

    const wikiAutoCompletion = new AiHelperAutoCompletion(wikiTextarea, {
      contextType: 'wiki',
      endpoint: endpoint,
      userId: config.userId,
      debounceDelay: config.debounceDelay,
      minLength: config.minLength,
      suggestionColor: config.suggestionColor,
      customRequestData: function(text, cursorPosition) {
        return {
          text: text,
          cursor_position: cursorPosition,
          context_type: 'wiki',
          is_section_edit: config.isSectionEdit
        };
      },
      labels: {
        commonToggleLabel: config.labels.commonToggleLabel,
        loading: config.labels.loading,
        noSuggestions: config.labels.noSuggestions,
        acceptSuggestion: config.labels.acceptSuggestion,
        dismiss: config.labels.dismiss,
        enabledTooltip: config.labels.enabledTooltip,
        disabledTooltip: config.labels.disabledTooltip
      }
    });

    wikiAutoCompletion.init();

    const wikiContainer = document.getElementById('ai-helper-wiki-checkbox-container');
    if (wikiContainer && wikiTextarea) {
      const parent = wikiTextarea.parentNode;
      const nextSibling = wikiTextarea.nextSibling;
      if (nextSibling) {
        parent.insertBefore(wikiContainer, nextSibling);
      } else {
        parent.appendChild(wikiContainer);
      }
      wikiContainer.style.display = 'block';
    }

    if (!window.aiHelperInstances) {
      window.aiHelperInstances = {};
    }
    window.aiHelperInstances.wikiAutoCompletion = wikiAutoCompletion;
  }

  window.aiHelperWikiCompletionInitialized = true;
}

/**
 * Bind the typo-check button/overlay for the wiki content textarea.
 */
function initializeWikiTextareaTypoChecker() {
  const container = document.getElementById('ai-helper-wiki-typo-overlay');
  if (container) {
    window.AiHelperTypoChecker.initFromConfig(container, 'content_text', 'ai-helper-typo-check-wiki-btn');
  }
}

document.addEventListener('DOMContentLoaded', function() {
  initializeWikiCompletion();
  initializeWikiTextareaTypoChecker();
});
