class AiHelper {
  ai_helper_urls = {};
  page_info = {
    additional_info: {}
  };
  local_storage_key = "aihelper-fold-flag";

  set_form_handlers = function () {
    // Prevent the default submit behavior of the form
    const form = document.getElementById("ai_helper_chat_form");
    form.addEventListener("submit", function (e) {
      e.preventDefault();
    });

    // Click event for #aihelper-chat-submit button
    const submitButton = document.getElementById("aihelper-chat-submit");
    submitButton.addEventListener("click", function (e) {
      e.preventDefault();
      submitAction();
      return false;
    });

    // submitAction
    function submitAction() {
      document.getElementById("ai_helper_controller_name").value = ai_helper.page_info["controller_name"];
      document.getElementById("ai_helper_action_name").value = ai_helper.page_info["action_name"];
      document.getElementById("ai_helper_content_id").value = ai_helper.page_info["content_id"];

      // Get form data
      const textInput = document.getElementById("ai_helper_chat_input");
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
    const chatInput = document.getElementById("ai_helper_chat_input");
    chatInput.addEventListener("keydown", function (e) {
      if (e.key === "Enter") {
        if (e.shiftKey) {
            // Allow line break when Shift + Enter is pressed
          return true;
        } else if (e.isComposing || e.keyCode === 229) {
            // Ignore Enter key when confirming IME (e.g., for kanji conversion)
          return true;
        } else {
            // If only Enter is pressed, trigger submit
          e.preventDefault();
          submitAction();
          return false;
        }
      }
    });
  };

  // SSE stream processing helper
  handleSSEStream = function(xhr, onContentCallback, onCompleteCallback) {
    let fullResponse = '';
    let buffer = '';
    let lastProcessedIndex = 0;

    xhr.onprogress = function (event) {
      const text = xhr.responseText.substring(lastProcessedIndex);
      lastProcessedIndex = xhr.responseText.length;
      buffer += text;

      // Extract data from Server-Sent Events
      const matches = buffer.match(/^data: (.+?)\n\n/gm);
      if (matches) {
        matches.forEach(match => {
          try {
            const dataStr = match.replace(/^data: /, '').trim();
            const data = JSON.parse(dataStr);

            // Get content from chunk
            const content = data.choices[0]?.delta?.content;
            if (content) {
              fullResponse += content;
              if (onContentCallback) {
                onContentCallback(content, fullResponse);
              }
            }

            if (data.choices[0]?.finish_reason === 'stop') {
              if (onCompleteCallback) {
                onCompleteCallback(fullResponse);
              }
            }
          } catch (e) {
            console.error('Parse error:', e);
          }

          // Remove processed data from buffer
          buffer = buffer.replace(match, '');
        });
      }
    };
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

        const loaderArea = document.getElementById("ai-helper-loader-area");
        if (loaderArea) {
          loaderArea.style.display = "none";
        }
      },
      // onCompleteCallback
      function(fullResponse) {
        ai_helper.reload_chat();
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

  reload_chat = function () {
    const chatArea = document.getElementById("aihelper-chat-conversation");
    if (!chatArea) return;

    const xhr = new XMLHttpRequest();
    xhr.open("GET", ai_helper_urls.reload, true);

    xhr.onload = function () {
      if (xhr.status === 200) {
        ai_helper.innerHTMLwithScripts(chatArea, xhr.responseText);
        chatArea.scrollTop = chatArea.scrollHeight;
      } else {
        console.error("Failed to reload chat conversation:", xhr.statusText);
      }
    };

    xhr.onerror = function () {
      console.error("Failed to reload chat conversation:", xhr.statusText);
    };

    xhr.send();
  };

  load_history() {
    const historyContainer = document.getElementById("aihelper-history");
    if (!historyContainer) return;

    const xhr = new XMLHttpRequest();
    xhr.open("GET", ai_helper_urls.history, true);

    xhr.onload = function () {
      if (xhr.status === 200) {
        ai_helper.innerHTMLwithScripts(historyContainer, xhr.responseText);
      } else {
        console.error("Failed to reload chat conversation:", xhr.statusText);
      }
    };

    xhr.onerror = function () {
      console.error("Failed to reload chat conversation:", xhr.statusText);
    };

    xhr.send();
  };

  clear_chat = function () {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", ai_helper_urls.clear, true);

    xhr.onload = function () {
      if (xhr.status === 200) {
        ai_helper.close_dropdown_menu();
        ai_helper.reload_chat();
      } else {
        console.error("Failed to reload chat conversation:", xhr.statusText);
      }
    };

    xhr.onerror = function () {
      console.error("Failed to reload chat conversation:", xhr.statusText);
    };

    xhr.send();
  };

  set_hamberger_menu() {
    // Click event for hamburger menu
    const hamburgerButtons = document.querySelectorAll(".aihelper-hamburger");
    hamburgerButtons.forEach(button => {
      button.addEventListener("click", function (event) {
        ai_helper.load_history();
        event.stopPropagation();
        this.classList.toggle("active");

        const dropdownMenu = document.querySelector(".aihelper-dropdown-menu");
        if (dropdownMenu) {
          if (dropdownMenu.style.display === "none" || !dropdownMenu.style.display) {
            dropdownMenu.style.display = "block";
            // Animation effect
            const height = dropdownMenu.scrollHeight;
            dropdownMenu.style.height = "0px";
            dropdownMenu.style.overflow = "hidden";
            dropdownMenu.style.transition = "height 300ms";
            setTimeout(() => {
              dropdownMenu.style.height = height + "px";
            }, 10);
            setTimeout(() => {
              dropdownMenu.style.height = "";
              dropdownMenu.style.overflow = "";
              dropdownMenu.style.transition = "";
            }, 310);
          } else {
            // Animation effect
            const height = dropdownMenu.scrollHeight;
            dropdownMenu.style.height = height + "px";
            dropdownMenu.style.overflow = "hidden";
            dropdownMenu.style.transition = "height 300ms";
            setTimeout(() => {
              dropdownMenu.style.height = "0px";
            }, 10);
            setTimeout(() => {
              dropdownMenu.style.display = "none";
              dropdownMenu.style.height = "";
              dropdownMenu.style.overflow = "";
              dropdownMenu.style.transition = "";
            }, 310);
          }
        }
      });
    });

    // Stop propagation of click events inside the dropdown menu
    const dropdownMenus = document.querySelectorAll(".aihelper-dropdown-menu");
    dropdownMenus.forEach(menu => {
      menu.addEventListener("click", function (event) {
        event.stopPropagation();
      });
    });

    // Close the dropdown menu when clicking anywhere on the document
    document.addEventListener("click", function () {
      ai_helper.close_dropdown_menu();
    });
  };

  close_dropdown_menu = function () {
    const hamburgerButtons = document.querySelectorAll(".aihelper-hamburger");
    hamburgerButtons.forEach(button => {
      button.classList.remove("active");
    });

    const dropdownMenus = document.querySelectorAll(".aihelper-dropdown-menu");
    dropdownMenus.forEach(menu => {
      // Alternative for animation effect
      const height = menu.scrollHeight;
      menu.style.height = height + "px";
      menu.style.overflow = "hidden";
      menu.style.transition = "height 300ms";
      setTimeout(() => {
        menu.style.height = "0px";
      }, 10);
      setTimeout(() => {
        menu.style.display = "none";
        menu.style.height = "";
        menu.style.overflow = "";
        menu.style.transition = "";
      }, 310);
    });
  };

  jump_to_history = function (event, url) {
    event.preventDefault();
    const chatArea = document.getElementById("aihelper-chat-conversation");
    if (!chatArea) return;

    const xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);

    xhr.onload = function () {
      if (xhr.status === 200) {
        ai_helper.close_dropdown_menu();
        ai_helper.fold_chat(false);
        ai_helper.innerHTMLwithScripts(chatArea, xhr.responseText);
        chatArea.scrollTop = 0;
      } else {
        console.error("Failed to reload chat conversation:", xhr.statusText);
      }
    };

    xhr.onerror = function () {
      console.error("Failed to reload chat conversation:", xhr.statusText);
    };

    xhr.send();
  };

  delete_history = function (event, url) {
    event.preventDefault();
    const xhr = new XMLHttpRequest();
    xhr.open("DELETE", url, true);

    // Add CSRF token to header if needed
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    if (csrfToken) {
      xhr.setRequestHeader('X-CSRF-Token', csrfToken);
    }

    xhr.onload = function () {
      if (xhr.status === 200) {
        ai_helper.load_history();
        try {
          const data = JSON.parse(xhr.responseText);
          if (data["reload"]) {
            ai_helper.reload_chat();
          }
        } catch (e) {
          console.error("Failed to parse response:", e);
        }
      } else {
        console.error("Failed to reload chat conversation:", xhr.statusText);
      }
    };

    xhr.onerror = function () {
      console.error("Failed to reload chat conversation:", xhr.statusText);
    };

    xhr.send();
  };

  fold_chat = function (flag, disable_animation = false) {
    const chatArea = document.getElementById("aihelper-foldable-area");
    const arrow_down = document.getElementById("aihelper-arrow-down");
    const arrow_left = document.getElementById("aihelper-arrow-left");

    if (!chatArea || !arrow_down || !arrow_left) return;

    if (flag) {
      if (disable_animation) {
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
      arrow_down.style.display = "none";
      arrow_left.style.display = "block";
    } else {
      if (disable_animation) {
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
      arrow_down.style.display = "block";
      arrow_left.style.display = "none";
    }
    // Save the flag value to local storage
    localStorage.setItem(this.local_storage_key, flag);
  };

  init_fold_flag = function () {
    const flag = localStorage.getItem(this.local_storage_key);
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
    if (!replyEl) return;
    const replyContent = replyEl.textContent.trim();
    const replyInputArea = document.getElementById("issue_notes");
    if (!replyInputArea) return;
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

  generateSummaryStream = function(generateSummaryUrl, summaryErrorText) {
    const summaryArea = document.getElementById('ai-helper-summary-area');
    const url = generateSummaryUrl;

    // Set up streaming content area
    const streamingContent = document.createElement('div');
    streamingContent.id = 'ai-helper-streaming-summary';
    streamingContent.style.padding = '10px';
    streamingContent.style.marginTop = '10px';
    streamingContent.style.whiteSpace = 'pre-wrap';

    const loader = document.createElement('div');
    loader.className = 'ai-helper-loader';

    summaryArea.innerHTML = '';
    summaryArea.appendChild(loader);
    summaryArea.appendChild(streamingContent);

    const xhr = new XMLHttpRequest();
    xhr.open('POST', url, true);
    xhr.setRequestHeader('Content-Type', 'application/json');

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    if (csrfToken) {
      xhr.setRequestHeader('X-CSRF-Token', csrfToken);
    }

    xhr.responseType = 'text';

    // Use the common SSE handler
    this.handleSSEStream(xhr,
      // onContentCallback
      function(_content, fullResponse) {
        streamingContent.textContent = fullResponse;

        // Hide loader on first content
        if (loader.style.display !== 'none') {
          loader.style.display = 'none';
        }
      },
      // onCompleteCallback
      function(_fullResponse) {
        // Reload the summary display to show cached version
        setTimeout(() => {
          getSummary();
        }, 1000);
      }
    );

    xhr.onerror = function () {
      loader.style.display = 'none';
      streamingContent.textContent = summaryErrorText;
    };

    xhr.onload = function () {
      if (xhr.status !== 200) {
        loader.style.display = 'none';
        streamingContent.textContent = `Error: ${xhr.status} ${xhr.statusText}`;
      }
    };

    xhr.send('{}');
  }

  generateReplyStream = function(generateReplyUrl, instructions, errorText, applyButtonText, copyButtonText) {
    const replyArea = document.getElementById('ai-helper-generate_reply-area');
    replyArea.style.display = '';

    // Initialize streaming response area
    const streamingContent = document.createElement('div');
    streamingContent.id = 'ai-helper-streaming-reply';

    const loader = document.createElement('div');
    loader.className = 'ai-helper-loader';

    replyArea.innerHTML = '';
    replyArea.appendChild(loader);
    replyArea.appendChild(streamingContent);

    const xhr = new XMLHttpRequest();
    xhr.open('POST', generateReplyUrl, true);
    xhr.setRequestHeader('Content-Type', 'application/json');

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    if (csrfToken) {
      xhr.setRequestHeader('X-CSRF-Token', csrfToken);
    }

    xhr.responseType = 'text';

    // Use the common SSE handler
    this.handleSSEStream(xhr,
      // onContentCallback
      function(_content, fullResponse) {
        streamingContent.textContent = fullResponse;

        // Hide loader on first content
        if (loader.style.display !== 'none') {
          loader.style.display = 'none';
        }
      },
      // onCompleteCallback
      function(fullResponse) {
        // Create apply button
        const applyButton = document.createElement('button');
        applyButton.type = 'button';
        applyButton.textContent = applyButtonText;
        applyButton.onclick = function(e) {
          e.preventDefault();
          const issueNotes = document.getElementById("issue_notes");
          if (issueNotes) {
            issueNotes.value = fullResponse;
          }
          return false;
        };

        // Create copy link
        const copyLink = document.createElement('a');
        copyLink.href = '#';
        copyLink.className = 'icon icon-copy-link';
        copyLink.innerHTML = copyButtonText;
        copyLink.onclick = function(e) {
          e.preventDefault();
          navigator.clipboard.writeText(fullResponse);
          return false;
        };

        replyArea.appendChild(applyButton);
        replyArea.appendChild(copyLink);
      }
    );

    xhr.onerror = function () {
      loader.style.display = 'none';
      streamingContent.textContent = errorText;
    };

    xhr.onload = function () {
      if (xhr.status !== 200) {
        loader.style.display = 'none';
        streamingContent.textContent = `Error: ${xhr.status} ${xhr.statusText}`;
      }
    };

    xhr.send(JSON.stringify({ instructions: instructions }));
  }

  generateWikiSummaryStream = function(generateSummaryUrl, summaryErrorText) {
    const summaryArea = document.getElementById('ai-helper-wiki-summary-area');

    // Set up streaming content area
    const streamingContent = document.createElement('div');
    streamingContent.id = 'ai-helper-streaming-wiki-summary';
    streamingContent.style.padding = '10px';
    streamingContent.style.marginTop = '10px';
    streamingContent.style.whiteSpace = 'pre-wrap';

    const loader = document.createElement('div');
    loader.className = 'ai-helper-loader';

    summaryArea.innerHTML = '';
    summaryArea.appendChild(loader);
    summaryArea.appendChild(streamingContent);

    const xhr = new XMLHttpRequest();
    xhr.open('POST', generateSummaryUrl, true);
    xhr.setRequestHeader('Content-Type', 'application/json');

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    if (csrfToken) {
      xhr.setRequestHeader('X-CSRF-Token', csrfToken);
    }

    xhr.responseType = 'text';

    // Use the common SSE handler
    this.handleSSEStream(xhr,
      // onContentCallback
      function(_content, fullResponse) {
        streamingContent.textContent = fullResponse;

        // Hide loader on first content
        if (loader.style.display !== 'none') {
          loader.style.display = 'none';
        }
      },
      // onCompleteCallback
      function(_fullResponse) {
        // Reload the summary display to show cached version
        setTimeout(() => {
          getWikiSummary();
        }, 1000);
      }
    );

    xhr.onerror = function () {
      loader.style.display = 'none';
      streamingContent.textContent = summaryErrorText;
    };

    xhr.onload = function () {
      if (xhr.status !== 200) {
        loader.style.display = 'none';
        streamingContent.textContent = `Error: ${xhr.status} ${xhr.statusText}`;
      }
    };

    xhr.send('{}');
  }
};

var ai_helper = new AiHelper();
