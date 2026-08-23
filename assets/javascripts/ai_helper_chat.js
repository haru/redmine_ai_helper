/**
 * Chat sidebar and form initialization logic.
 * Extracted from _chat_form.html.erb and _sidebar.html.erb.
 */
const AiHelperChat = (() => {
  /**
   * Initialize CommandCompletion on the chat input if not already done.
   */
  function initChatForm() {
    const chatInput = document.getElementById('ai-helper-message-input');
    if (chatInput && !chatInput.dataset.commandCompletionInitialized) {
      const commandsUrl = chatInput.dataset.commandsUrl;
      if (typeof CommandCompletion !== 'undefined') {
        new CommandCompletion(chatInput, commandsUrl);
        chatInput.dataset.commandCompletionInitialized = 'true';
      }
    }
  }

  /**
   * Initialize the chat sidebar: relocate into sidebar-wrapper, load chat
   * form via XHR, and wire up ai_helper page info.
   *
   * Reads configuration from the #aihelper-sidebar element's data attributes:
   * - data-chat-form-url
   * - data-content-id
   * - data-controller-name
   * - data-action-name
   * - data-additional-info (JSON string)
   */
  function initSidebar() {
    if (!document.getElementById('sidebar-wrapper')) {
      return;
    }

    const sidebarElement = document.getElementById('aihelper-sidebar');
    const sidebarWrapper = document.getElementById('sidebar-wrapper');
    if (sidebarElement && sidebarWrapper) {
      sidebarWrapper.insertBefore(sidebarElement, sidebarWrapper.firstChild);
    }

    ai_helper.init_fold_flag();
    ai_helper.reload_chat();

    const chatForm = document.getElementById('aihelper-chat-form-area');
    const formUrl = sidebarElement ? sidebarElement.dataset.chatFormUrl : undefined;

    if (chatForm && formUrl) {
      const xhr = new XMLHttpRequest();
      xhr.open('GET', formUrl, true);
      xhr.onload = function() {
        if (xhr.status === 200) {
          ai_helper.innerHTMLwithScripts(chatForm, xhr.responseText);
        }
      };
      xhr.send();
    }

    if (sidebarElement) {
      ai_helper.page_info['content_id'] = sidebarElement.dataset.contentId || '';
      ai_helper.page_info['controller_name'] = sidebarElement.dataset.controllerName || '';
      ai_helper.page_info['action_name'] = sidebarElement.dataset.actionName || '';

      try {
        const additionalInfo = JSON.parse(sidebarElement.dataset.additionalInfo || '{}');
        for (const key in additionalInfo) {
          if (Object.prototype.hasOwnProperty.call(additionalInfo, key)) {
            ai_helper.page_info['additional_info'][key] = String(additionalInfo[key]);
          }
        }
      } catch (error) {
        console.error('AiHelperChat: failed to parse sidebar additional-info JSON; repository path/revision/diff context will be unavailable', error, sidebarElement.dataset.additionalInfo);
      }
    }

    ai_helper.set_hamberger_menu();
  }

  return {
    initChatForm,
    initSidebar,
  };
})();

window.AiHelperChat = AiHelperChat;
