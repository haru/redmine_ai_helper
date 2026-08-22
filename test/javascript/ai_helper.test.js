import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "./support/load_script.js";

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
    await loadScript("assets/javascripts/ai_helper_markdown_parser");
    await loadScript("assets/javascripts/ai_helper");
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
    if (meta) meta.remove();
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

  describe("handleSSEStream", () => {
    it("parses SSE data chunks and calls onContentCallback", () => {
      const chunks = [];
      helper.handleSSEStream(
        xhr,
        (content) => chunks.push(content),
        null,
        null
      );

      xhr.responseText = 'data: {"choices":[{"delta":{"content":"Hello"}}]}\n';
      xhr.onprogress();

      expect(chunks).toEqual(["Hello"]);
    });

    it("accumulates content across multiple chunks", () => {
      const fullResponses = [];
      helper.handleSSEStream(
        xhr,
        (_content, fullResponse) => fullResponses.push(fullResponse),
        null,
        null
      );

      xhr.responseText = 'data: {"choices":[{"delta":{"content":"Hello"}}]}' + '\n\n';
      xhr.onprogress();
      xhr.responseText += 'data: {"choices":[{"delta":{"content":" World"}}]}' + '\n\n';
      xhr.onprogress();

      expect(fullResponses).toEqual(["Hello", "Hello World"]);
    });

    it("calls onCompleteCallback on finish_reason stop", () => {
      let completed = false;
      helper.handleSSEStream(
        xhr,
        null,
        () => { completed = true; },
        null
      );

      xhr.responseText = 'data: {"choices":[{"delta":{"content":"Hi"},"finish_reason":"stop"}]}' + '\n\n';
      xhr.onprogress();

      expect(completed).toBe(true);
    });

    it("handles interactive_options event type", () => {
      let options = null;
      helper.handleSSEStream(
        xhr,
        null,
        null,
        (choices) => { options = choices; }
      );

      xhr.responseText = 'event: interactive_options\ndata: {"choices":[{"label":"A","value":"a"}]}\n\n';
      xhr.onprogress();

      expect(options).toEqual([{ label: "A", value: "a" }]);
    });

    it("handles malformed JSON gracefully", () => {
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
      const chunks = [];
      helper.handleSSEStream(
        xhr,
        (c) => chunks.push(c),
        null,
        null
      );

      xhr.responseText = 'data: {invalid json}\n';
      xhr.onprogress();

      expect(chunks).toEqual([]);
      expect(consoleError).toHaveBeenCalled();
      consoleError.mockRestore();
    });

    it("handles empty line resetting pending event type", () => {
      let options = null;
      helper.handleSSEStream(
        xhr,
        null,
        null,
        (choices) => { options = choices; }
      );

      xhr.responseText = 'event: interactive_options\n\n';
      xhr.onprogress();

      expect(options).toBeNull();
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
  });

  describe("close_dropdown_menu", () => {
    it("removes active class from hamburger and closes dropdown", () => {
      dom.hamburger.classList.add("active");
      dom.dropdownMenu.style.display = "block";
      vi.useFakeTimers();

      helper.close_dropdown_menu();

      vi.advanceTimersByTime(400);

      expect(dom.hamburger.classList.contains("active")).toBe(false);
      vi.useRealTimers();
    });

    it("works when no hamburger buttons exist", () => {
      dom.hamburger.remove();
      expect(() => helper.close_dropdown_menu()).not.toThrow();
    });
  });

  describe("generateSummaryStream", () => {
    it("creates streaming content area and sends POST request", () => {
      const summaryArea = document.createElement("div");
      summaryArea.id = "ai-helper-summary-area";
      document.body.appendChild(summaryArea);

      helper.generateSummaryStream("/summary/url", "Error text");

      expect(xhr.open).toHaveBeenCalledWith("POST", "/summary/url", true);
      expect(xhr.setRequestHeader).toHaveBeenCalledWith(
        "Content-Type", "application/json"
      );

      summaryArea.remove();
    });

    it("sends CSRF token in header", () => {
      const summaryArea = document.createElement("div");
      summaryArea.id = "ai-helper-summary-area";
      document.body.appendChild(summaryArea);

      helper.generateSummaryStream("/summary/url", "Error");

      expect(xhr.setRequestHeader).toHaveBeenCalledWith(
        "X-CSRF-Token", "test-csrf-token"
      );

      summaryArea.remove();
    });
  });

  describe("generateReplyStream", () => {
    it("creates streaming content area and sends POST with instructions", () => {
      const replyArea = document.createElement("div");
      replyArea.id = "ai-helper-generate_reply-area";
      replyArea.style.display = "none";
      document.body.appendChild(replyArea);

      helper.generateReplyStream(
        "/reply/url",
        "Fix the bug",
        "Error text",
        "Apply",
        "Copy"
      );

      expect(xhr.open).toHaveBeenCalledWith("POST", "/reply/url", true);
      const sentData = JSON.parse(xhr.send.mock.calls[0][0]);
      expect(sentData.instructions).toBe("Fix the bug");

      replyArea.remove();
    });
  });

  describe("generateWikiSummaryStream", () => {
    it("creates streaming content and sends POST request", () => {
      const wikiSummaryArea = document.createElement("div");
      wikiSummaryArea.id = "ai-helper-wiki-summary-area";
      document.body.appendChild(wikiSummaryArea);

      helper.generateWikiSummaryStream("/wiki/summary/url", "Wiki Error");

      expect(xhr.open).toHaveBeenCalledWith("POST", "/wiki/summary/url", true);

      wikiSummaryArea.remove();
    });
  });


  describe("static parseSSELines", () => {
    function contentLine(text) {
      return 'data: {"choices":[{"delta":{"content":"' + text + '"}}]}'
    }
    function stopLine(text) {
      return 'data: {"choices":[{"delta":{"content":"' + text + '"},"finish_reason":"stop"}]}'
    }

    it("parses a content data line", () => {
      const result = window.AiHelper.parseSSELines(
        [contentLine("Hello")],
        null, "",
        () => {}, null, null
      );
      expect(result.fullResponse).toBe("Hello");
      expect(result.eventType).toBeNull();
    });

    it("returns pending event type for event lines", () => {
      const result = window.AiHelper.parseSSELines(
        ["event: interactive_options"],
        null, "",
        null, null, null
      );
      expect(result.eventType).toBe("interactive_options");
    });

    it("handles interactive_options event", () => {
      let choices = null;
      const result = window.AiHelper.parseSSELines(
        ["event: interactive_options", 'data: {"choices":[{"label":"A"}]}'],
        null, "",
        null, null, (c) => { choices = c; }
      );
      expect(choices).toEqual([{ label: "A" }]);
      expect(result.eventType).toBeNull();
    });

    it("accumulates content across multiple data lines", () => {
      const chunks = [];
      window.AiHelper.parseSSELines(
        [contentLine("Hello"), contentLine(" World")],
        null, "",
        (_c, full) => chunks.push(full), null, null
      );
      expect(chunks).toEqual(["Hello", "Hello World"]);
    });

    it("calls onComplete on finish_reason stop", () => {
      let completed = false;
      window.AiHelper.parseSSELines(
        [stopLine("Hi")],
        null, "",
        null, () => { completed = true; }, null
      );
      expect(completed).toBe(true);
    });

    it("handles malformed JSON gracefully", () => {
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
      const result = window.AiHelper.parseSSELines(
        ["data: {invalid}"],
        null, "",
        () => {}, null, null
      );
      expect(result.fullResponse).toBe("");
      expect(consoleError).toHaveBeenCalled();
      consoleError.mockRestore();
    });

    it("resets pending event type on empty line", () => {
      const result = window.AiHelper.parseSSELines(
        ["event: interactive_options", ""],
        null, "",
        null, null, null
      );
      expect(result.eventType).toBeNull();
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

  describe("reload_chat", () => {
    it("does nothing when the chat conversation area is absent", () => {
      dom.chatConversation.remove();
      expect(() => helper.reload_chat()).not.toThrow();
      expect(xhr.open).not.toHaveBeenCalled();
    });

    it("hides interactive options and issues a GET request", () => {
      dom.interactiveOptions.hidden = false;

      helper.reload_chat();

      expect(dom.interactiveOptions.hidden).toBe(true);
      expect(xhr.open).toHaveBeenCalledWith("GET", "/ai_helper/reload", true);
    });

    it("replaces the conversation content on success", () => {
      helper.reload_chat();

      xhr.status = 200;
      xhr.responseText = "<p>new content</p>";
      xhr.onload();

      expect(dom.chatConversation.innerHTML).toContain("new content");
    });

    it("logs an error on a non-200 response", () => {
      helper.reload_chat();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

      xhr.status = 500;
      xhr.statusText = "Server Error";
      xhr.onload();

      expect(errorSpy).toHaveBeenCalledWith("Failed to reload chat conversation:", "Server Error");
      errorSpy.mockRestore();
    });

    it("logs an error on xhr.onerror", () => {
      helper.reload_chat();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

      xhr.onerror();

      expect(errorSpy).toHaveBeenCalled();
      errorSpy.mockRestore();
    });
  });

  describe("load_history", () => {
    it("does nothing when the history container is absent", () => {
      dom.historyEl.remove();
      expect(() => helper.load_history()).not.toThrow();
      expect(xhr.open).not.toHaveBeenCalled();
    });

    it("fetches and renders the history on success", () => {
      helper.load_history();

      expect(xhr.open).toHaveBeenCalledWith("GET", "/ai_helper/history", true);

      xhr.status = 200;
      xhr.responseText = "<li>entry</li>";
      xhr.onload();

      expect(dom.historyEl.innerHTML).toContain("entry");
    });

    it("logs an error on a non-200 response", () => {
      helper.load_history();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

      xhr.status = 500;
      xhr.onload();

      expect(errorSpy).toHaveBeenCalled();
      errorSpy.mockRestore();
    });

    it("logs an error on xhr.onerror", () => {
      helper.load_history();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

      xhr.onerror();

      expect(errorSpy).toHaveBeenCalled();
      errorSpy.mockRestore();
    });
  });

  describe("clear_chat", () => {
    it("closes the dropdown and reloads the chat on success", () => {
      helper.clear_chat();

      expect(xhr.open).toHaveBeenCalledWith("GET", "/ai_helper/clear", true);

      const closeSpy = vi.spyOn(helper, "close_dropdown_menu").mockImplementation(() => {});
      const reloadSpy = vi.spyOn(helper, "reload_chat").mockImplementation(() => {});
      xhr.status = 200;
      xhr.onload();

      expect(closeSpy).toHaveBeenCalledTimes(1);
      expect(reloadSpy).toHaveBeenCalledTimes(1);
    });

    it("logs an error on a non-200 response", () => {
      helper.clear_chat();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

      xhr.status = 500;
      xhr.onload();

      expect(errorSpy).toHaveBeenCalled();
      errorSpy.mockRestore();
    });

    it("logs an error on xhr.onerror", () => {
      helper.clear_chat();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

      xhr.onerror();

      expect(errorSpy).toHaveBeenCalled();
      errorSpy.mockRestore();
    });
  });

  describe("set_hamberger_menu", () => {
    // set_hamberger_menu() registers a document-level click listener each
    // time it runs; document persists across tests in this file, so it must
    // be removed afterwards or later tests would trigger every prior test's
    // listener too.
    let documentClickListener;

    function callSetHambergerMenu() {
      const spy = vi.spyOn(document, "addEventListener");
      helper.set_hamberger_menu();
      const call = spy.mock.calls.find(([type]) => type === "click");
      documentClickListener = call ? call[1] : undefined;
      spy.mockRestore();
    }

    afterEach(() => {
      if (documentClickListener) document.removeEventListener("click", documentClickListener);
      documentClickListener = undefined;
    });

    it("loads history, toggles active class, and opens the dropdown", () => {
      const loadHistorySpy = vi.spyOn(helper, "load_history").mockImplementation(() => {});
      callSetHambergerMenu();

      const clickEvent = new MouseEvent("click", { bubbles: true, cancelable: true });
      const stopSpy = vi.spyOn(clickEvent, "stopPropagation");
      dom.hamburger.dispatchEvent(clickEvent);

      expect(loadHistorySpy).toHaveBeenCalledTimes(1);
      expect(stopSpy).toHaveBeenCalled();
      expect(dom.hamburger.classList.contains("active")).toBe(true);
      expect(dom.dropdownMenu.style.display).toBe("block");
    });

    it("closes an already-open dropdown on a second click", () => {
      vi.spyOn(helper, "load_history").mockImplementation(() => {});
      vi.useFakeTimers();
      callSetHambergerMenu();

      dom.hamburger.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      dom.hamburger.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      vi.advanceTimersByTime(400);
      expect(dom.dropdownMenu.style.display).toBe("none");
      vi.useRealTimers();
    });

    it("stops propagation for clicks inside the dropdown menu", () => {
      vi.spyOn(helper, "load_history").mockImplementation(() => {});
      callSetHambergerMenu();

      const event = new MouseEvent("click", { bubbles: true, cancelable: true });
      const stopSpy = vi.spyOn(event, "stopPropagation");
      dom.dropdownMenu.dispatchEvent(event);

      expect(stopSpy).toHaveBeenCalled();
    });

    it("closes the dropdown when clicking anywhere else on the document", () => {
      vi.spyOn(helper, "load_history").mockImplementation(() => {});
      const closeSpy = vi.spyOn(helper, "close_dropdown_menu");
      callSetHambergerMenu();

      document.body.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(closeSpy).toHaveBeenCalledTimes(1);
    });
  });

  describe("jump_to_history and delete_history (chained requests)", () => {
    function createXhrQueueMock() {
      const instances = [];
      vi.stubGlobal(
        "XMLHttpRequest",
        class {
          constructor() {
            this.open = vi.fn();
            this.send = vi.fn();
            this.setRequestHeader = vi.fn();
            this.responseText = "";
            this.status = 200;
            this.statusText = "OK";
            this.onload = null;
            this.onerror = null;
            instances.push(this);
          }
        },
      );
      return instances;
    }

    it("jump_to_history prevents default, closes the dropdown, unfolds, and renders the response", () => {
      const instances = createXhrQueueMock();
      const closeSpy = vi.spyOn(helper, "close_dropdown_menu").mockImplementation(() => {});
      const foldSpy = vi.spyOn(helper, "fold_chat").mockImplementation(() => {});
      const event = { preventDefault: vi.fn() };

      helper.jump_to_history(event, "/ai_helper/history/1");

      expect(event.preventDefault).toHaveBeenCalled();
      expect(instances[0].open).toHaveBeenCalledWith("GET", "/ai_helper/history/1", true);

      instances[0].status = 200;
      instances[0].responseText = "<p>history entry</p>";
      instances[0].onload();

      expect(closeSpy).toHaveBeenCalledTimes(1);
      expect(foldSpy).toHaveBeenCalledWith(false);
      expect(dom.chatConversation.innerHTML).toContain("history entry");
    });

    it("jump_to_history does nothing when the chat conversation area is absent", () => {
      const instances = createXhrQueueMock();
      dom.chatConversation.remove();
      const event = { preventDefault: vi.fn() };

      helper.jump_to_history(event, "/ai_helper/history/1");

      expect(event.preventDefault).toHaveBeenCalled();
      expect(instances.length).toBe(0);
    });

    it("jump_to_history logs an error on a non-200 response", () => {
      const instances = createXhrQueueMock();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
      helper.jump_to_history({ preventDefault: vi.fn() }, "/x");

      instances[0].status = 500;
      instances[0].onload();

      expect(errorSpy).toHaveBeenCalled();
      errorSpy.mockRestore();
    });

    it("jump_to_history logs an error on xhr.onerror", () => {
      const instances = createXhrQueueMock();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
      helper.jump_to_history({ preventDefault: vi.fn() }, "/x");

      instances[0].onerror();

      expect(errorSpy).toHaveBeenCalled();
      errorSpy.mockRestore();
    });

    it("delete_history sends the CSRF token, reloads history, and reloads the chat when told to", () => {
      const instances = createXhrQueueMock();
      const loadHistorySpy = vi.spyOn(helper, "load_history").mockImplementation(() => {});
      const reloadSpy = vi.spyOn(helper, "reload_chat").mockImplementation(() => {});
      const event = { preventDefault: vi.fn() };

      helper.delete_history(event, "/ai_helper/history/1");

      expect(event.preventDefault).toHaveBeenCalled();
      expect(instances[0].open).toHaveBeenCalledWith("DELETE", "/ai_helper/history/1", true);
      expect(instances[0].setRequestHeader).toHaveBeenCalledWith("X-CSRF-Token", "test-csrf-token");

      instances[0].status = 200;
      instances[0].responseText = JSON.stringify({ reload: true });
      instances[0].onload();

      expect(loadHistorySpy).toHaveBeenCalledTimes(1);
      expect(reloadSpy).toHaveBeenCalledTimes(1);
    });

    it("delete_history does not reload the chat when the response says not to", () => {
      const instances = createXhrQueueMock();
      vi.spyOn(helper, "load_history").mockImplementation(() => {});
      const reloadSpy = vi.spyOn(helper, "reload_chat").mockImplementation(() => {});

      helper.delete_history({ preventDefault: vi.fn() }, "/x");
      instances[0].status = 200;
      instances[0].responseText = JSON.stringify({ reload: false });
      instances[0].onload();

      expect(reloadSpy).not.toHaveBeenCalled();
    });

    it("delete_history logs an error when the response is not valid JSON", () => {
      const instances = createXhrQueueMock();
      vi.spyOn(helper, "load_history").mockImplementation(() => {});
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

      helper.delete_history({ preventDefault: vi.fn() }, "/x");
      instances[0].status = 200;
      instances[0].responseText = "not json";
      instances[0].onload();

      expect(errorSpy).toHaveBeenCalledWith("Failed to parse response:", expect.any(Error));
      errorSpy.mockRestore();
    });

    it("delete_history logs an error on a non-200 response", () => {
      const instances = createXhrQueueMock();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

      helper.delete_history({ preventDefault: vi.fn() }, "/x");
      instances[0].status = 500;
      instances[0].onload();

      expect(errorSpy).toHaveBeenCalled();
      errorSpy.mockRestore();
    });

    it("delete_history logs an error on xhr.onerror", () => {
      const instances = createXhrQueueMock();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

      helper.delete_history({ preventDefault: vi.fn() }, "/x");
      instances[0].onerror();

      expect(errorSpy).toHaveBeenCalled();
      errorSpy.mockRestore();
    });
  });
});
