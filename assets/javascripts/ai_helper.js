class AiHelper {
  ai_helper_urls = {};
  page_info = {
    additional_info: {}
  };
  userId = 'anonymous';
  chat_fold_storage_key = 'aihelper-fold-flag_anonymous';
  interactiveOptionsHandlersInitialized = false;

  // Method to update user ID without recreating the instance
  setUserId(userId) {
    this.userId = userId;
    this.chat_fold_storage_key = `aihelper-fold-flag_${userId}`;
  }

  set_form_handlers = function () {
    // Prevent the default submit behavior of the form
    const form = document.getElementById("ai_helper_chat_form");
    if (!form) {
      return; // Chat form not present on this page
    }

    form.addEventListener("submit", function (e) {
      e.preventDefault();
    });

    // Click event for #aihelper-chat-submit button
    const submitButton = document.getElementById("aihelper-chat-submit");
    if (!submitButton) {
      return; // Submit button not present on this page
    }

    submitButton.addEventListener("click", function (e) {
      e.preventDefault();
      ai_helper.hideInteractiveOptions();
      submitAction();
      return false;
    });

    // submitAction
    function submitAction() {
      document.getElementById("ai_helper_controller_name").value = ai_helper.page_info["controller_name"];
      document.getElementById("ai_helper_action_name").value = ai_helper.page_info["action_name"];
      document.getElementById("ai_helper_content_id").value = ai_helper.page_info["content_id"];

      // Get form data
      const textInput = document.getElementById("ai-helper-message-input");
      const text = textInput.value;

      // Return if text is empty or contains only whitespace
      if (!text.trim()) {
        return;
      }

      const formData = new FormData(form);

      const xhr = new XMLHttpRequest();
      xhr.open("POST", form.getAttribute("action"), true);

      xhr.onload = function () {
        if (xhr.status === 200) {
          const chatConversation = document.getElementById("aihelper-chat-conversation");
          ai_helper.innerHTMLwithScripts(chatConversation, xhr.responseText);

          document.getElementById("ai-helper-loader-area").style.display = "block";
          form.reset();

          chatConversation.scrollTop = chatConversation.scrollHeight;
          ai_helper.call_llm();
        } else {
          console.error("Error:", xhr.statusText);
        }
      };

      xhr.onerror = function () {
        console.error("Error:", xhr.statusText);
      };

      xhr.send(formData);
    }

    // Key event handling for textarea
    const chatInput = document.getElementById("ai-helper-message-input");
    if (!chatInput) {
      return; // Chat input not present on this page
    }

    // Prevent Redmine's "unsaved changes" beforeunload dialog from triggering
    // for the chat input. Redmine listens for `change` on all textareas via a
    // delegated handler on `document`. Stopping propagation here keeps the event
    // local and the flag never gets set.
    chatInput.addEventListener("change", function (e) {
      e.stopPropagation();
    });

    chatInput.addEventListener("keydown", function (e) {
      if (e.key === "Enter") {
        if (e.shiftKey) {
            // Allow line break when Shift + Enter is pressed
          return true;
        } else if (e.isComposing || e.keyCode === 229) {
            // Ignore Enter key when confirming IME (e.g., for kanji conversion)
          return true;
        } else {
          // Check if command completion is active
          const commandCompletion = chatInput._commandCompletion;
          if (commandCompletion && commandCompletion.isSuggestionsVisible()) {
            // Let CommandCompletion handle the Enter key
            // Do NOT submit the form
            return;
          }
            // If only Enter is pressed, trigger submit
          e.preventDefault();
          submitAction();
          return false;
        }
      }
    });
  };

  // SSE parsing/streaming (static parseSSELines, handleSSEStream) live in
  // ai_helper_streaming.js — see the comment there for why.

  // Attach delegated click/keydown handlers to the container once
  initializeInteractiveOptionsHandlers = function(container) {
    if (this.interactiveOptionsHandlersInitialized) {return;}

    container.addEventListener('click', function(e) {
      const button = e.target.closest('.aihelper-option-btn');
      if (!button || !container.contains(button)) {return;}

      if (button.dataset.freeInput === 'true') {
        ai_helper.hideInteractiveOptions();
        const input = document.getElementById('ai-helper-message-input');
        if (input) { input.focus(); }
        return;
      }

      const input = document.getElementById('ai-helper-message-input');
      if (input) {
        input.value = button.dataset.value;
      }
      ai_helper.hideInteractiveOptions();
      const submitButton = document.getElementById('aihelper-chat-submit');
      if (submitButton) {
        submitButton.click();
      }
    });

    container.addEventListener('keydown', function(e) {
      const button = e.target.closest('.aihelper-option-btn');
      if (!button || !container.contains(button)) {return;}

      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        button.click();
      }
    });

    this.interactiveOptionsHandlersInitialized = true;
  };

  // Render interactive option buttons for the given choices array
  renderInteractiveOptions = function(choices) {
    const container = document.getElementById('aihelper-interactive-options');
    if (!container) {return;}

    if (!this.interactiveOptionsHandlersInitialized) {
      this.initializeInteractiveOptionsHandlers(container);
    }

    const buttons = Array.from(container.querySelectorAll('.aihelper-option-btn'))
      .filter(btn => btn.dataset.freeInput !== 'true');
    const freeInputBtn = container.querySelector('.aihelper-option-btn[data-free-input="true"]');

    // Show container and configure buttons
    container.hidden = false;

    buttons.forEach((btn, index) => {
      if (index < choices.length) {
        const choice = choices[index];
        btn.textContent = choice.label;
        btn.dataset.value = choice.value;
        btn.disabled = false;
        btn.hidden = false;
      } else {
        btn.hidden = true;
      }
    });

    if (freeInputBtn) {
      freeInputBtn.hidden = false;
    }
  };

  // Hide the interactive options container (on reload/clear)
  hideInteractiveOptions = function() {
    const container = document.getElementById('aihelper-interactive-options');
    if (container) {
      container.hidden = true;
    }
  };

  call_llm = function () {
    const url = ai_helper_urls.call_llm;
    const data = JSON.stringify(this.page_info);
    const xhr = new XMLHttpRequest();
    xhr.open('POST', url, true);
    xhr.setRequestHeader('Content-Type', 'application/json');

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    if (csrfToken) {
      xhr.setRequestHeader('X-CSRF-Token', csrfToken);
    }

    xhr.responseType = 'text';

    const parser = new AiHelperMarkdownParser();

    // Hide any existing interactive option buttons while waiting for new response
    ai_helper.hideInteractiveOptions();

    // Use the common SSE handler
    this.handleSSEStream(xhr,
      // onContentCallback
      function(content, fullResponse) {
        const lastMessage = document.getElementById('aihelper_last_message');
        if (lastMessage) {
          ai_helper.innerHTMLwithScripts(lastMessage, parser.parse(fullResponse));
        }

        const chatConversation = document.getElementById("aihelper-chat-conversation");
        if (chatConversation) {
          chatConversation.scrollTop = chatConversation.scrollHeight;
        }
      },
      // onCompleteCallback
      function() {
        const loaderArea = document.getElementById("ai-helper-loader-area");
        if (loaderArea) {
          loaderArea.style.display = "none";
        }

        ai_helper.reload_chat();
      },
      // onInteractiveOptionsCallback
      function(choices) {
        ai_helper.renderInteractiveOptions(choices);
      }
    );

    xhr.onerror = function () {
      const loaderArea = document.getElementById("ai-helper-loader-area");
      if (loaderArea) {
        loaderArea.style.display = "none";
      }

      const lastMessage = document.getElementById('aihelper_last_message');
      if (lastMessage) {
        lastMessage.textContent = 'An error has occurred';
      }
    };

    xhr.onload = function () {
      if (xhr.status !== 200) {
        const lastMessage = document.getElementById('aihelper_last_message');
        if (lastMessage) {
            lastMessage.textContent = `Error: ${xhr.status} ${xhr.statusText}`;
        }
      }
    };

    xhr.send(data);
  };

  setClearButtonVisible(flag) {
    const clearButton = document.getElementById("aihelper-chat-clear");
    if (clearButton) {
      if (flag) {
        clearButton.style.display = "block";
      } else {
        clearButton.style.display = "none";
      }
    }
  }

  // reload_chat, load_history, clear_chat, set_hamberger_menu,
  // close_dropdown_menu, jump_to_history, delete_history live in
  // ai_helper_history.js alongside the chat-history/dropdown-menu concern
  // they share.

  fold_chat = function (flag, disableAnimation = false) {
    const chatArea = document.getElementById("aihelper-foldable-area");
    const arrowDown = document.getElementById("aihelper-arrow-down");
    const arrowLeft = document.getElementById("aihelper-arrow-left");

    if (!chatArea || !arrowDown || !arrowLeft) {return;}

    if (flag) {
      if (disableAnimation) {
        chatArea.style.display = "none";
      } else {
        // Alternative for slideUp animation
        const height = chatArea.scrollHeight;
        chatArea.style.height = height + "px";
        chatArea.style.overflow = "hidden";
        chatArea.style.transition = "height 300ms";
        setTimeout(() => {
          chatArea.style.height = "0px";
        }, 10);
        setTimeout(() => {
          chatArea.style.display = "none";
          chatArea.style.height = "";
          chatArea.style.overflow = "";
          chatArea.style.transition = "";
        }, 310);
      }
      arrowDown.style.display = "none";
      arrowLeft.style.display = "block";
    } else {
      if (disableAnimation) {
        chatArea.style.display = "block";
      } else {
        // Alternative for slideDown animation
        chatArea.style.display = "block";
        const height = chatArea.scrollHeight;
        chatArea.style.height = "0px";
        chatArea.style.overflow = "hidden";
        chatArea.style.transition = "height 300ms";
        setTimeout(() => {
          chatArea.style.height = height + "px";
        }, 10);
        setTimeout(() => {
          chatArea.style.height = "";
          chatArea.style.overflow = "";
          chatArea.style.transition = "";
        }, 310);
      }
      arrowDown.style.display = "block";
      arrowLeft.style.display = "none";
    }
    // Save the flag value to local storage
    localStorage.setItem(this.chat_fold_storage_key, flag);
  };

  init_fold_flag = function () {
    const flag = localStorage.getItem(this.chat_fold_storage_key);
    if (flag === "true") {
      this.fold_chat(true, true);
    } else {
      this.fold_chat(false, true);
    }
  };

  innerHTMLwithScripts = function (element, html) {
    element.innerHTML = html;

    const scripts = element.querySelectorAll('script');
    scripts.forEach(script => {
      const newScript = document.createElement('script');
      newScript.textContent = script.textContent;
      document.body.appendChild(newScript);
    });


  }

  apply_generated_issue_reply = function () {
    const replyEl = document.getElementById("ai-helper-generated-reply-content");
    if (!replyEl) {return;}
    const replyContent = replyEl.textContent.trim();
    const replyInputArea = document.getElementById("issue_notes");
    if (!replyInputArea) {return;}
    // Set the reply content to the input area
    replyInputArea.value = replyContent;
  }

  edit_sub_issue_subject = function(i) {
    const subjectSpan = document.getElementById(`ai_helper_sub_issue_subject_${i}`);
    const subjectEditSpan = document.getElementById(`ai_helper_sub_issue_subject_edit_${i}`);

    subjectSpan.style.display = 'none';
    subjectEditSpan.style.display = 'inline';
  }

  apply_sub_issue_subject = function(i) {
    const subjectSpan = document.getElementById(`ai_helper_sub_issue_subject_${i}`);
    const subjectEditSpan = document.getElementById(`ai_helper_sub_issue_subject_edit_${i}`);
    const subjectInput = document.getElementById(`sub_issues_subject_field_${i}`);

    const newSubject = subjectInput.value.trim();
    // If newSubject is empty or contains only whitespace, do nothing and return
    if (!newSubject) {
      return;
    }
    const subjectChildSpan = subjectSpan.querySelector('span');
    if (subjectChildSpan) {
      subjectChildSpan.textContent = newSubject;
    }
    subjectSpan.style.display = 'inline';
    subjectEditSpan.style.display = 'none';
  }

  cancel_sub_issue_subject = function(i) {
    const subjectSpan = document.getElementById(`ai_helper_sub_issue_subject_${i}`);
    const subjectEditSpan = document.getElementById(`ai_helper_sub_issue_subject_edit_${i}`);

    const subjectInput = document.getElementById(`sub_issues_subject_field_${i}`);
    subjectInput.value = subjectSpan.querySelector('span').textContent.trim();

    subjectSpan.style.display = 'inline';
    subjectEditSpan.style.display = 'none';
  }

  edit_sub_issue_description = function(i) {
    const descriptionSpan = document.getElementById(`ai_helper_sub_issue_description_${i}`);
    const descriptionEditSpan = document.getElementById(`ai_helper_sub_issue_description_edit_${i}`);

    descriptionSpan.style.display = 'none';
    descriptionEditSpan.style.display = 'inline';
  }

  apply_sub_issue_description = function(i) {
    const descriptionSpan = document.getElementById(`ai_helper_sub_issue_description_${i}`);
    const descriptionEditSpan = document.getElementById(`ai_helper_sub_issue_description_edit_${i}`);
    const descriptionInput = document.getElementById(`sub_issues_description_field_${i}`);

    const newDescription = descriptionInput.value.trim();
    if (newDescription) {
      const descriptionChildSpan = descriptionSpan.querySelector('span');
      if (descriptionChildSpan) {
        descriptionChildSpan.textContent = newDescription;
      }
    }
    descriptionSpan.style.display = 'inline';
    descriptionEditSpan.style.display = 'none';
  }

  cancel_sub_issue_description = function(i) {
    const descriptionSpan = document.getElementById(`ai_helper_sub_issue_description_${i}`);
    const descriptionEditSpan = document.getElementById(`ai_helper_sub_issue_description_edit_${i}`);

    const descriptionInput = document.getElementById(`sub_issues_description_field_${i}`);
    descriptionInput.value = descriptionSpan.querySelector('span').textContent.trim();

    descriptionSpan.style.display = 'inline';
    descriptionEditSpan.style.display = 'none';
  }

  // generateSummaryStream, generateReplyStream, generateWikiSummaryStream
  // live in ai_helper_streaming.js alongside the SSE handler they share.
};

// Default instance for backward compatibility
window.AiHelper = AiHelper;
window.ai_helper = new AiHelper();
