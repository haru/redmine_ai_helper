import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";

function createAiHelperDOM() {
  const container = document.createElement("div");

  // Chat form
  const form = document.createElement("form");
  form.id = "ai_helper_chat_form";
  form.action = "/ai_helper/chat/send";

  const input = document.createElement("input");
  input.type = "hidden";
  input.id = "ai_helper_controller_name";
  form.appendChild(input);

  const actionInput = document.createElement("input");
  actionInput.type = "hidden";
  actionInput.id = "ai_helper_action_name";
  form.appendChild(actionInput);

  const contentIdInput = document.createElement("input");
  contentIdInput.type = "hidden";
  contentIdInput.id = "ai_helper_content_id";
  form.appendChild(contentIdInput);

  const textInput = document.createElement("textarea");
  textInput.id = "ai-helper-message-input";
  form.appendChild(textInput);

  const submitBtn = document.createElement("button");
  submitBtn.id = "aihelper-chat-submit";
  submitBtn.type = "button";
  form.appendChild(submitBtn);

  container.appendChild(form);

  // Chat conversation area
  const chatConversation = document.createElement("div");
  chatConversation.id = "aihelper-chat-conversation";
  container.appendChild(chatConversation);

  // Last message area
  const lastMessage = document.createElement("div");
  lastMessage.id = "aihelper_last_message";
  container.appendChild(lastMessage);

  // Loader
  const loader = document.createElement("div");
  loader.id = "ai-helper-loader-area";
  loader.style.display = "none";
  container.appendChild(loader);

  // Clear button
  const clearBtn = document.createElement("div");
  clearBtn.id = "aihelper-chat-clear";
  clearBtn.style.display = "none";
  container.appendChild(clearBtn);

  // Foldable area
  const foldArea = document.createElement("div");
  foldArea.id = "aihelper-foldable-area";
  foldArea.style.display = "block";
  container.appendChild(foldArea);

  const arrowDown = document.createElement("div");
  arrowDown.id = "aihelper-arrow-down";
  arrowDown.style.display = "block";
  container.appendChild(arrowDown);

  const arrowLeft = document.createElement("div");
  arrowLeft.id = "aihelper-arrow-left";
  arrowLeft.style.display = "none";
  container.appendChild(arrowLeft);

  // Hamburger menu
  const hamburger = document.createElement("div");
  hamburger.className = "aihelper-hamburger";
  container.appendChild(hamburger);

  const dropdownMenu = document.createElement("div");
  dropdownMenu.className = "aihelper-dropdown-menu";
  dropdownMenu.style.display = "none";
  container.appendChild(dropdownMenu);

  // History
  const historyEl = document.createElement("div");
  historyEl.id = "aihelper-history";
  container.appendChild(historyEl);

  // Interactive options
  const interactiveOptions = document.createElement("div");
  interactiveOptions.id = "aihelper-interactive-options";
  interactiveOptions.hidden = true;
  for (let i = 0; i < 5; i++) {
    const btn = document.createElement("button");
    btn.className = "aihelper-option-btn";
    btn.hidden = true;
    interactiveOptions.appendChild(btn);
  }
  const freeInputBtn = document.createElement("button");
  freeInputBtn.className = "aihelper-option-btn";
  freeInputBtn.dataset.freeInput = "true";
  freeInputBtn.hidden = true;
  interactiveOptions.appendChild(freeInputBtn);
  container.appendChild(interactiveOptions);

  // CSRF meta tag
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "test-csrf-token";
  document.head.appendChild(meta);

  document.body.appendChild(container);

  return {
    container,
    form,
    textInput,
    submitBtn,
    chatConversation,
    lastMessage,
    loader,
    clearBtn,
    foldArea,
    arrowDown,
    arrowLeft,
    hamburger,
    dropdownMenu,
    historyEl,
    interactiveOptions,
  };
}

function createXhrMock() {
  const xhr = {
    open: vi.fn(),
    send: vi.fn(),
    setRequestHeader: vi.fn(),
    responseText: "",
    status: 200,
    statusText: "OK",
    onprogress: null,
    onload: null,
    onerror: null,
    responseType: "text",
  };
  vi.stubGlobal("XMLHttpRequest", function () {
    return xhr;
  });
  return xhr;
}

describe("AiHelper", () => {
  let dom;
  let helper;
  let xhr;

  beforeEach(async () => {
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
    await loadScript("assets/javascripts/chat/ai_helper");
    await loadScript("assets/javascripts/chat/ai_helper_streaming");
    await loadScript("assets/javascripts/chat/ai_helper_history");
    dom = createAiHelperDOM();
    xhr = createXhrMock();
    window.ai_helper_urls = {
      call_llm: "/ai_helper/call_llm",
      reload: "/ai_helper/reload",
      history: "/ai_helper/history",
      clear: "/ai_helper/clear",
    };
    helper = window.ai_helper;
    helper.page_info = {
      controller_name: "issues",
      action_name: "show",
      content_id: "1",
      additional_info: {},
    };
  });

  afterEach(() => {
    localStorage.clear();
    if (dom && dom.container && dom.container.parentNode) {
      dom.container.remove();
    }
    const meta = document.querySelector('meta[name="csrf-token"]');
    if (meta) {meta.remove();}
    delete window.ai_helper_urls;
    vi.unstubAllGlobals();
  });

  describe("setUserId", () => {
    it("updates userId and storage key", () => {
      helper.setUserId("user123");
      expect(helper.userId).toBe("user123");
      expect(helper.chat_fold_storage_key).toBe("aihelper-fold-flag_user123");
    });
  });

  describe("fold_chat", () => {
    it("folds the chat area and swaps arrows", () => {
      vi.useFakeTimers();
      helper.fold_chat(true);

      vi.advanceTimersByTime(400);

      expect(dom.foldArea.style.display).toBe("none");
      expect(dom.arrowDown.style.display).toBe("none");
      expect(dom.arrowLeft.style.display).toBe("block");
      vi.useRealTimers();
    });

    it("unfolds the chat area and swaps arrows", () => {
      helper.fold_chat(true, true);
      expect(dom.foldArea.style.display).toBe("none");
      expect(dom.arrowLeft.style.display).toBe("block");

      helper.fold_chat(false, true);
      expect(dom.foldArea.style.display).toBe("block");
      expect(dom.arrowDown.style.display).toBe("block");
      expect(dom.arrowLeft.style.display).toBe("none");
    });

    it("unfolds with animation when disableAnimation is false", () => {
      vi.useFakeTimers();
      helper.fold_chat(true, true);

      helper.fold_chat(false);

      expect(dom.foldArea.style.display).toBe("block");
      expect(dom.foldArea.style.transition).toBe("height 300ms");

      vi.advanceTimersByTime(20);
      expect(dom.foldArea.style.height).toBe(dom.foldArea.scrollHeight + "px");

      vi.advanceTimersByTime(400);
      expect(dom.foldArea.style.height).toBe("");
      expect(dom.foldArea.style.transition).toBe("");
      vi.useRealTimers();
    });

    it("saves fold state to localStorage", () => {
      helper.fold_chat(true, true);
      expect(localStorage.getItem(helper.chat_fold_storage_key)).toBe("true");

      helper.fold_chat(false, true);
      expect(localStorage.getItem(helper.chat_fold_storage_key)).toBe("false");
    });

    it("does nothing when required elements are missing", () => {
      dom.foldArea.remove();
      expect(() => helper.fold_chat(true, true)).not.toThrow();
    });
  });

  describe("init_fold_flag", () => {
    it("folds chat when localStorage has true", () => {
      localStorage.setItem(helper.chat_fold_storage_key, "true");
      helper.init_fold_flag();
      expect(dom.foldArea.style.display).toBe("none");
    });

    it("unfolds chat when localStorage has false", () => {
      localStorage.setItem(helper.chat_fold_storage_key, "false");
      helper.init_fold_flag();
      expect(dom.foldArea.style.display).toBe("block");
    });

    it("unfolds chat when localStorage has no value", () => {
      helper.init_fold_flag();
      expect(dom.foldArea.style.display).toBe("block");
    });
  });

  describe("setClearButtonVisible", () => {
    it("shows the clear button when flag is true", () => {
      helper.setClearButtonVisible(true);
      expect(dom.clearBtn.style.display).toBe("block");
    });

    it("hides the clear button when flag is false", () => {
      helper.setClearButtonVisible(false);
      expect(dom.clearBtn.style.display).toBe("none");
    });

    it("does nothing when clear button is not in DOM", () => {
      dom.clearBtn.remove();
      expect(() => helper.setClearButtonVisible(true)).not.toThrow();
    });
  });

  describe("innerHTMLwithScripts", () => {
    it("sets innerHTML and creates new script elements in body", () => {
      const el = document.createElement("div");
      const scriptContent = "window.__testScriptExecuted = true";

      helper.innerHTMLwithScripts(el, `<p>Hello</p><script>${scriptContent}</script>`);

      expect(el.innerHTML).toContain("<p>Hello</p>");
      // A new script element was appended to document.body
      const bodyScripts = Array.from(document.body.querySelectorAll('script'));
      const found = bodyScripts.some(s => s.textContent.includes("__testScriptExecuted"));
      expect(found).toBe(true);
      delete window.__testScriptExecuted;
    });
  });

  describe("apply_generated_issue_reply", () => {
    it("copies reply content to issue notes textarea", () => {
      const replyEl = document.createElement("div");
      replyEl.id = "ai-helper-generated-reply-content";
      replyEl.textContent = "Generated reply text";
      document.body.appendChild(replyEl);

      const notesArea = document.createElement("textarea");
      notesArea.id = "issue_notes";
      document.body.appendChild(notesArea);

      helper.apply_generated_issue_reply();

      expect(notesArea.value).toBe("Generated reply text");

      replyEl.remove();
      notesArea.remove();
    });

    it("does nothing when reply element is absent", () => {
      expect(() => helper.apply_generated_issue_reply()).not.toThrow();
    });
  });

  describe("sub issue subject editing", () => {
    it("edit_sub_issue_subject shows edit span", () => {
      const span = document.createElement("span");
      span.id = "ai_helper_sub_issue_subject_0";
      span.style.display = "inline";
      const editSpan = document.createElement("span");
      editSpan.id = "ai_helper_sub_issue_subject_edit_0";
      editSpan.style.display = "none";
      document.body.appendChild(span);
      document.body.appendChild(editSpan);

      helper.edit_sub_issue_subject(0);

      expect(span.style.display).toBe("none");
      expect(editSpan.style.display).toBe("inline");

      span.remove();
      editSpan.remove();
    });

    it("apply_sub_issue_subject updates text", () => {
      const span = document.createElement("span");
      span.id = "ai_helper_sub_issue_subject_0";
      const childSpan = document.createElement("span");
      childSpan.textContent = "Old Subject";
      span.appendChild(childSpan);
      const editSpan = document.createElement("span");
      editSpan.id = "ai_helper_sub_issue_subject_edit_0";
      editSpan.style.display = "inline";
      const input = document.createElement("input");
      input.id = "sub_issues_subject_field_0";
      input.value = "New Subject";
      editSpan.appendChild(input);
      span.style.display = "none";
      document.body.appendChild(span);
      document.body.appendChild(editSpan);

      helper.apply_sub_issue_subject(0);

      expect(childSpan.textContent).toBe("New Subject");
      expect(span.style.display).toBe("inline");
      expect(editSpan.style.display).toBe("none");

      span.remove();
      editSpan.remove();
    });

    it("apply_sub_issue_subject does nothing when new subject is empty", () => {
      const span = document.createElement("span");
      span.id = "ai_helper_sub_issue_subject_0";
      const editSpan = document.createElement("span");
      editSpan.id = "ai_helper_sub_issue_subject_edit_0";
      const input = document.createElement("input");
      input.id = "sub_issues_subject_field_0";
      input.value = "  ";
      editSpan.appendChild(input);
      document.body.appendChild(span);
      document.body.appendChild(editSpan);

      helper.apply_sub_issue_subject(0);
      expect(span.style.display).not.toBe("inline");

      span.remove();
      editSpan.remove();
    });

    it("cancel_sub_issue_subject restores original text", () => {
      const span = document.createElement("span");
      span.id = "ai_helper_sub_issue_subject_0";
      const childSpan = document.createElement("span");
      childSpan.textContent = "Original Subject";
      span.appendChild(childSpan);
      const editSpan = document.createElement("span");
      editSpan.id = "ai_helper_sub_issue_subject_edit_0";
      editSpan.style.display = "inline";
      const input = document.createElement("input");
      input.id = "sub_issues_subject_field_0";
      input.value = "Changed";
      editSpan.appendChild(input);
      document.body.appendChild(span);
      document.body.appendChild(editSpan);

      helper.cancel_sub_issue_subject(0);

      expect(input.value).toBe("Original Subject");
      expect(span.style.display).toBe("inline");

      span.remove();
      editSpan.remove();
    });
  });

  describe("sub issue description editing", () => {
    it("edit_sub_issue_description shows edit span", () => {
      const span = document.createElement("span");
      span.id = "ai_helper_sub_issue_description_0";
      span.style.display = "inline";
      const editSpan = document.createElement("span");
      editSpan.id = "ai_helper_sub_issue_description_edit_0";
      editSpan.style.display = "none";
      document.body.appendChild(span);
      document.body.appendChild(editSpan);

      helper.edit_sub_issue_description(0);

      expect(span.style.display).toBe("none");
      expect(editSpan.style.display).toBe("inline");

      span.remove();
      editSpan.remove();
    });

    it("apply_sub_issue_description updates text when non-empty", () => {
      const span = document.createElement("span");
      span.id = "ai_helper_sub_issue_description_0";
      const childSpan = document.createElement("span");
      childSpan.textContent = "Old Desc";
      span.appendChild(childSpan);
      const editSpan = document.createElement("span");
      editSpan.id = "ai_helper_sub_issue_description_edit_0";
      const input = document.createElement("input");
      input.id = "sub_issues_description_field_0";
      input.value = "New Desc";
      editSpan.appendChild(input);
      document.body.appendChild(span);
      document.body.appendChild(editSpan);

      helper.apply_sub_issue_description(0);

      expect(childSpan.textContent).toBe("New Desc");

      span.remove();
      editSpan.remove();
    });

    it("apply_sub_issue_description does nothing when description is empty", () => {
      const span = document.createElement("span");
      span.id = "ai_helper_sub_issue_description_0";
      const editSpan = document.createElement("span");
      editSpan.id = "ai_helper_sub_issue_description_edit_0";
      const input = document.createElement("input");
      input.id = "sub_issues_description_field_0";
      input.value = "";
      editSpan.appendChild(input);
      document.body.appendChild(span);
      document.body.appendChild(editSpan);

      helper.apply_sub_issue_description(0);

      span.remove();
      editSpan.remove();
    });

    it("cancel_sub_issue_description restores original text", () => {
      const span = document.createElement("span");
      span.id = "ai_helper_sub_issue_description_0";
      const childSpan = document.createElement("span");
      childSpan.textContent = "Original Desc";
      span.appendChild(childSpan);
      const editSpan = document.createElement("span");
      editSpan.id = "ai_helper_sub_issue_description_edit_0";
      const input = document.createElement("input");
      input.id = "sub_issues_description_field_0";
      input.value = "Changed";
      editSpan.appendChild(input);
      document.body.appendChild(span);
      document.body.appendChild(editSpan);

      helper.cancel_sub_issue_description(0);

      expect(input.value).toBe("Original Desc");

      span.remove();
      editSpan.remove();
    });
  });

  describe("interactive options", () => {
    it("initializeInteractiveOptionsHandlers sets up once", () => {
      helper.initializeInteractiveOptionsHandlers(dom.interactiveOptions);
      expect(helper.interactiveOptionsHandlersInitialized).toBe(true);

      // Second call should be a no-op
      helper.initializeInteractiveOptionsHandlers(dom.interactiveOptions);
      expect(helper.interactiveOptionsHandlersInitialized).toBe(true);
    });

    it("renderInteractiveOptions shows buttons with choices", () => {
      helper.initializeInteractiveOptionsHandlers(dom.interactiveOptions);
      helper.renderInteractiveOptions([
        { label: "Option A", value: "a" },
        { label: "Option B", value: "b" },
      ]);

      expect(dom.interactiveOptions.hidden).toBe(false);
      const btns = dom.interactiveOptions.querySelectorAll(
        ".aihelper-option-btn:not([data-free-input])"
      );
      expect(btns[0].textContent).toBe("Option A");
      expect(btns[0].dataset.value).toBe("a");
      expect(btns[0].hidden).toBe(false);
      expect(btns[1].textContent).toBe("Option B");
      expect(btns[2].hidden).toBe(true);
    });

    it("renderInteractiveOptions shows free input button", () => {
      helper.initializeInteractiveOptionsHandlers(dom.interactiveOptions);
      helper.renderInteractiveOptions([]);

      const freeBtn = dom.interactiveOptions.querySelector(
        '.aihelper-option-btn[data-free-input="true"]'
      );
      expect(freeBtn.hidden).toBe(false);
    });

    it("hideInteractiveOptions hides the container", () => {
      helper.initializeInteractiveOptionsHandlers(dom.interactiveOptions);
      dom.interactiveOptions.hidden = false;

      helper.hideInteractiveOptions();

      expect(dom.interactiveOptions.hidden).toBe(true);
    });

    it("hideInteractiveOptions does nothing when container is absent", () => {
      expect(() => helper.hideInteractiveOptions()).not.toThrow();
    });

    it("clicking an option button sets input value and submits", () => {
      helper.initializeInteractiveOptionsHandlers(dom.interactiveOptions);
      helper.renderInteractiveOptions([
        { label: "Option A", value: "a" },
      ]);

      const btn = dom.interactiveOptions.querySelector(
        '.aihelper-option-btn:not([data-free-input])'
      );
      btn.click();

      expect(dom.textInput.value).toBe("a");
      expect(dom.interactiveOptions.hidden).toBe(true);
    });

    it("clicking free input button focuses the input without submitting", () => {
      helper.initializeInteractiveOptionsHandlers(dom.interactiveOptions);
      helper.renderInteractiveOptions([]);

      const freeBtn = dom.interactiveOptions.querySelector(
        '.aihelper-option-btn[data-free-input="true"]'
      );
      const focusSpy = vi.spyOn(dom.textInput, "focus");
      freeBtn.click();

      expect(dom.interactiveOptions.hidden).toBe(true);
      expect(focusSpy).toHaveBeenCalled();
    });

    it("Enter key on option button triggers click", () => {
      helper.initializeInteractiveOptionsHandlers(dom.interactiveOptions);
      helper.renderInteractiveOptions([
        { label: "Option A", value: "a" },
      ]);

      const btn = dom.interactiveOptions.querySelector(
        '.aihelper-option-btn:not([data-free-input])'
      );
      btn.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));

      expect(dom.textInput.value).toBe("a");
      expect(dom.interactiveOptions.hidden).toBe(true);
    });

    it("Space key on option button triggers click", () => {
      helper.initializeInteractiveOptionsHandlers(dom.interactiveOptions);
      helper.renderInteractiveOptions([
        { label: "Option B", value: "b" },
      ]);

      const btn = dom.interactiveOptions.querySelector(
        '.aihelper-option-btn:not([data-free-input])'
      );
      btn.dispatchEvent(new KeyboardEvent("keydown", { key: " ", bubbles: true }));

      expect(dom.textInput.value).toBe("b");
    });
  });

  describe("set_form_handlers", () => {
    it("does nothing when the chat form is absent", () => {
      dom.form.remove();
      expect(() => helper.set_form_handlers()).not.toThrow();
    });

    it("does nothing when the submit button is absent", () => {
      dom.submitBtn.remove();
      expect(() => helper.set_form_handlers()).not.toThrow();
    });

    it("does nothing when the message input is absent", () => {
      dom.textInput.remove();
      expect(() => helper.set_form_handlers()).not.toThrow();
    });

    it("prevents the default form submit behavior", () => {
      helper.set_form_handlers();
      const event = new Event("submit", { bubbles: true, cancelable: true });
      dom.form.dispatchEvent(event);
      expect(event.defaultPrevented).toBe(true);
    });

    it("does not send a request when the submit button is clicked with empty text", () => {
      helper.set_form_handlers();
      dom.textInput.value = "   ";

      dom.submitBtn.click();

      expect(xhr.send).not.toHaveBeenCalled();
    });

    it("populates hidden fields and posts the message when the submit button is clicked", () => {
      helper.set_form_handlers();
      dom.textInput.value = "Hello there";

      dom.submitBtn.click();

      expect(document.getElementById("ai_helper_controller_name").value).toBe("issues");
      expect(document.getElementById("ai_helper_action_name").value).toBe("show");
      expect(document.getElementById("ai_helper_content_id").value).toBe("1");
      expect(xhr.open).toHaveBeenCalledWith("POST", "/ai_helper/chat/send", true);
      expect(xhr.send).toHaveBeenCalledTimes(1);
    });

    it("hides interactive options when the submit button is clicked", () => {
      dom.interactiveOptions.hidden = false;
      helper.set_form_handlers();
      dom.textInput.value = "Hi";

      dom.submitBtn.click();

      expect(dom.interactiveOptions.hidden).toBe(true);
    });

    it("renders the response and reloads the LLM call on a successful submit", () => {
      helper.set_form_handlers();
      dom.textInput.value = "Hi";
      dom.submitBtn.click();

      const callLlmSpy = vi.spyOn(helper, "call_llm").mockImplementation(() => {});
      xhr.status = 200;
      xhr.responseText = "<p>response</p>";
      xhr.onload();

      expect(dom.chatConversation.innerHTML).toContain("response");
      expect(dom.loader.style.display).toBe("block");
      expect(callLlmSpy).toHaveBeenCalledTimes(1);
    });

    it("logs an error when the submit response is not 200", () => {
      helper.set_form_handlers();
      dom.textInput.value = "Hi";
      dom.submitBtn.click();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

      xhr.status = 500;
      xhr.statusText = "Server Error";
      xhr.onload();

      expect(errorSpy).toHaveBeenCalledWith("Error:", "Server Error");
      errorSpy.mockRestore();
    });

    it("logs an error on xhr.onerror during submit", () => {
      helper.set_form_handlers();
      dom.textInput.value = "Hi";
      dom.submitBtn.click();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

      xhr.onerror();

      expect(errorSpy).toHaveBeenCalled();
      errorSpy.mockRestore();
    });

    it("stops propagation of the chat input's change event", () => {
      helper.set_form_handlers();
      const event = new Event("change", { bubbles: true });
      const stopSpy = vi.spyOn(event, "stopPropagation");

      dom.textInput.dispatchEvent(event);

      expect(stopSpy).toHaveBeenCalled();
    });

    it("submits on Enter without shift", () => {
      helper.set_form_handlers();
      dom.textInput.value = "Hi";

      const event = new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true });
      dom.textInput.dispatchEvent(event);

      expect(event.defaultPrevented).toBe(true);
      expect(xhr.send).toHaveBeenCalledTimes(1);
    });

    it("allows a line break on Shift+Enter without submitting", () => {
      helper.set_form_handlers();
      dom.textInput.value = "Hi";

      const event = new KeyboardEvent("keydown", { key: "Enter", shiftKey: true, bubbles: true, cancelable: true });
      dom.textInput.dispatchEvent(event);

      expect(event.defaultPrevented).toBe(false);
      expect(xhr.send).not.toHaveBeenCalled();
    });

    it("ignores Enter while composing an IME conversion", () => {
      helper.set_form_handlers();
      dom.textInput.value = "Hi";

      const event = new KeyboardEvent("keydown", { key: "Enter", isComposing: true, bubbles: true, cancelable: true });
      dom.textInput.dispatchEvent(event);

      expect(event.defaultPrevented).toBe(false);
      expect(xhr.send).not.toHaveBeenCalled();
    });

    it("lets command completion handle Enter when its suggestions are visible", () => {
      helper.set_form_handlers();
      dom.textInput.value = "/";
      dom.textInput._commandCompletion = { isSuggestionsVisible: () => true };

      const event = new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true });
      dom.textInput.dispatchEvent(event);

      expect(event.defaultPrevented).toBe(false);
      expect(xhr.send).not.toHaveBeenCalled();
    });

    it("submits on Enter when command completion has no visible suggestions", () => {
      helper.set_form_handlers();
      dom.textInput.value = "Hi";
      dom.textInput._commandCompletion = { isSuggestionsVisible: () => false };

      const event = new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true });
      dom.textInput.dispatchEvent(event);

      expect(event.defaultPrevented).toBe(true);
      expect(xhr.send).toHaveBeenCalledTimes(1);
    });
  });

  describe("call_llm", () => {
    it("posts the page info with the CSRF token and hides interactive options", () => {
      dom.interactiveOptions.hidden = false;

      helper.call_llm();

      expect(xhr.open).toHaveBeenCalledWith("POST", "/ai_helper/call_llm", true);
      expect(xhr.setRequestHeader).toHaveBeenCalledWith("Content-Type", "application/json");
      expect(xhr.setRequestHeader).toHaveBeenCalledWith("X-CSRF-Token", "test-csrf-token");
      expect(JSON.parse(xhr.send.mock.calls[0][0])).toMatchObject({ controller_name: "issues" });
      expect(dom.interactiveOptions.hidden).toBe(true);
    });

    it("streams content into the last message and scrolls the conversation", () => {
      helper.call_llm();

      xhr.onprogress();
      Object.assign(xhr, { responseText: 'data: {"choices":[{"delta":{"content":"Hi"}}]}\n' });
      xhr.onprogress();

      expect(dom.lastMessage.innerHTML).toContain("Hi");
    });

    it("hides the loader and reloads the chat when the stream completes", () => {
      const reloadSpy = vi.spyOn(helper, "reload_chat").mockImplementation(() => {});
      dom.loader.style.display = "block";
      helper.call_llm();

      xhr.responseText = 'data: {"choices":[{"delta":{"content":"Hi"},"finish_reason":"stop"}]}\n';
      xhr.onprogress();

      expect(dom.loader.style.display).toBe("none");
      expect(reloadSpy).toHaveBeenCalledTimes(1);
    });

    it("renders interactive options via the SSE callback", () => {
      helper.call_llm();

      xhr.responseText = 'event: interactive_options\ndata: {"choices":[{"label":"Yes","value":"yes"}]}\n\n';
      xhr.onprogress();

      expect(dom.interactiveOptions.hidden).toBe(false);
    });

    it("shows an error message in the last message area on xhr.onerror", () => {
      dom.loader.style.display = "block";
      helper.call_llm();

      xhr.onerror();

      expect(dom.loader.style.display).toBe("none");
      expect(dom.lastMessage.textContent).toBe("An error has occurred");
    });

    it("shows the HTTP status in the last message area on a non-200 response", () => {
      helper.call_llm();

      xhr.status = 500;
      xhr.statusText = "Server Error";
      xhr.onload();

      expect(dom.lastMessage.textContent).toBe("Error: 500 Server Error");
    });

    it("does not touch the last message area on a successful response", () => {
      helper.call_llm();
      dom.lastMessage.textContent = "unchanged";

      xhr.status = 200;
      xhr.onload();

      expect(dom.lastMessage.textContent).toBe("unchanged");
    });
  });
});
