import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";

describe("AiHelperChat.initChatForm (from _chat_form.html.erb)", () => {
  let chatInput;
  let commandCompletionMock;
  let popupMock;

  beforeEach(() => {
    chatInput = document.createElement("textarea");
    chatInput.id = "ai-helper-message-input";
    chatInput.dataset.commandsUrl = "/projects/test/ai_helper/available_custom_commands";
    document.body.appendChild(chatInput);

    commandCompletionMock = vi.fn();
    vi.stubGlobal("CommandCompletion", commandCompletionMock);
    popupMock = { init: vi.fn(), restoreDraft: vi.fn() };
    vi.stubGlobal("AiHelperChatPopup", popupMock);
  });

  afterEach(() => {
    chatInput.remove();
    vi.unstubAllGlobals();
    delete window.AiHelperChat;
  });

  async function load() {
    await loadScript("assets/javascripts/chat/ai_helper_chat");
  }

  it("creates a CommandCompletion instance when the input exists and CommandCompletion is defined", async () => {
    await load();
    window.AiHelperChat.initChatForm();

    expect(commandCompletionMock).toHaveBeenCalledTimes(1);
    expect(commandCompletionMock).toHaveBeenCalledWith(chatInput, "/projects/test/ai_helper/available_custom_commands");
    expect(chatInput.dataset.commandCompletionInitialized).toBe("true");
  });

  it("does not create a second CommandCompletion when already initialized", async () => {
    await load();
    window.AiHelperChat.initChatForm();
    commandCompletionMock.mockClear();
    window.AiHelperChat.initChatForm();

    expect(commandCompletionMock).not.toHaveBeenCalled();
  });

  it("does nothing when the chat input element does not exist", async () => {
    chatInput.remove();
    await load();
    window.AiHelperChat.initChatForm();

    expect(commandCompletionMock).not.toHaveBeenCalled();
  });

  it("does nothing when CommandCompletion is not defined", async () => {
    vi.stubGlobal("CommandCompletion", undefined);
    await load();
    window.AiHelperChat.initChatForm();

    expect(chatInput.dataset.commandCompletionInitialized).toBeUndefined();
  });

  it("restores the popup draft once the chat form is initialized", async () => {
    await load();
    window.AiHelperChat.initChatForm();

    expect(popupMock.restoreDraft).toHaveBeenCalledTimes(1);
  });

  it("restores the popup draft even when the chat input is absent", async () => {
    chatInput.remove();
    await load();
    window.AiHelperChat.initChatForm();

    expect(popupMock.restoreDraft).toHaveBeenCalledTimes(1);
  });
});

describe("AiHelperChat.initSidebar (from _sidebar.html.erb)", () => {
  let sidebarWrapper;
  let sidebar;
  let chatFormArea;
  let aiHelperMock;
  let popupMock;

  beforeEach(() => {
    sidebarWrapper = document.createElement("div");
    sidebarWrapper.id = "sidebar-wrapper";
    document.body.appendChild(sidebarWrapper);

    chatFormArea = document.createElement("div");
    chatFormArea.id = "aihelper-chat-form-area";

    sidebar = document.createElement("div");
    sidebar.id = "aihelper-sidebar";
    sidebar.dataset.chatFormUrl = "/projects/test/ai_helper/chat_form";
    sidebar.dataset.contentId = "42";
    sidebar.dataset.controllerName = "issues";
    sidebar.dataset.actionName = "show";
    sidebar.dataset.additionalInfo = JSON.stringify({});
    sidebar.appendChild(chatFormArea);

    aiHelperMock = {
      init_fold_flag: vi.fn(),
      reload_chat: vi.fn(),
      innerHTMLwithScripts: vi.fn(),
      set_hamberger_menu: vi.fn(),
      page_info: { additional_info: {} },
    };
    vi.stubGlobal("ai_helper", aiHelperMock);
    popupMock = { init: vi.fn(), restoreDraft: vi.fn() };
    vi.stubGlobal("AiHelperChatPopup", popupMock);
  });

  afterEach(() => {
    sidebarWrapper.remove();
    // Some tests append the sidebar to <body> instead of the wrapper.
    sidebar.remove();
    vi.unstubAllGlobals();
    delete window.AiHelperChat;
  });

  async function load() {
    await loadScript("assets/javascripts/chat/ai_helper_chat");
  }

  it("moves aihelper-sidebar to be the first child of sidebar-wrapper", async () => {
    const otherDiv = document.createElement("div");
    sidebarWrapper.appendChild(otherDiv);
    sidebarWrapper.appendChild(sidebar);

    await load();
    window.AiHelperChat.initSidebar();

    expect(sidebarWrapper.firstChild).toBe(sidebar);
  });

  it("calls ai_helper.init_fold_flag, reload_chat, and set_hamberger_menu", async () => {
    sidebarWrapper.appendChild(sidebar);

    await load();
    window.AiHelperChat.initSidebar();

    expect(aiHelperMock.init_fold_flag).toHaveBeenCalled();
    expect(aiHelperMock.reload_chat).toHaveBeenCalled();
    expect(aiHelperMock.set_hamberger_menu).toHaveBeenCalled();
  });

  it("loads the chat form via XHR and inserts via innerHTMLwithScripts", async () => {
    sidebarWrapper.appendChild(sidebar);
    let createdInstance;
    function MockXHR() {
      this.open = vi.fn();
      this.send = vi.fn();
      this.status = 200;
      this.responseText = "<form>test</form>";
      this.onload = null;
      createdInstance = this;
    }
    vi.stubGlobal("XMLHttpRequest", MockXHR);

    await load();
    window.AiHelperChat.initSidebar();

    expect(createdInstance.open).toHaveBeenCalledWith("GET", "/projects/test/ai_helper/chat_form", true);

    createdInstance.onload();
    expect(aiHelperMock.innerHTMLwithScripts).toHaveBeenCalledWith(chatFormArea, "<form>test</form>");
  });

  it("sets page_info from dataset attributes", async () => {
    sidebarWrapper.appendChild(sidebar);
    sidebar.dataset.contentId = "99";
    sidebar.dataset.controllerName = "wiki";
    sidebar.dataset.actionName = "show";
    sidebar.dataset.additionalInfo = JSON.stringify({ path: "/src", rev: "abc" });

    await load();
    window.AiHelperChat.initSidebar();

    expect(aiHelperMock.page_info["content_id"]).toBe("99");
    expect(aiHelperMock.page_info["controller_name"]).toBe("wiki");
    expect(aiHelperMock.page_info["action_name"]).toBe("show");
    expect(aiHelperMock.page_info.additional_info["path"]).toBe("/src");
    expect(aiHelperMock.page_info.additional_info["rev"]).toBe("abc");
  });

  it("returns early when sidebar-wrapper does not exist", async () => {
    sidebarWrapper.remove();
    document.body.appendChild(sidebar);

    await load();
    window.AiHelperChat.initSidebar();

    expect(aiHelperMock.init_fold_flag).not.toHaveBeenCalled();
    expect(popupMock.init).not.toHaveBeenCalled();
  });

  it("initializes the chat popup after the sidebar has been moved to the top of the wrapper and set up", async () => {
    const other = document.createElement("div");
    sidebarWrapper.appendChild(other);
    sidebarWrapper.appendChild(sidebar);
    expect(sidebarWrapper.firstChild).not.toBe(sidebar);
    const order = [];
    aiHelperMock.set_hamberger_menu.mockImplementation(() => order.push("hamburger"));
    popupMock.init.mockImplementation(() => order.push(sidebarWrapper.firstChild === sidebar ? "popup-after-move" : "popup-before-move"));

    await load();
    window.AiHelperChat.initSidebar();

    expect(order).toEqual(["hamburger", "popup-after-move"]);
  });

  it("removes aihelper-popup-pending from <html> even when a setup step throws", async () => {
    sidebarWrapper.appendChild(sidebar);
    document.documentElement.classList.add("aihelper-popup-pending");
    aiHelperMock.reload_chat.mockImplementation(() => {
      throw new Error("reload failed");
    });

    await load();
    try {
      expect(() => window.AiHelperChat.initSidebar()).toThrow(/reload failed/);
      expect(document.documentElement.classList.contains("aihelper-popup-pending")).toBe(false);
    } finally {
      document.documentElement.classList.remove("aihelper-popup-pending");
    }
  });

  it("removes aihelper-popup-pending from <html> when there is no sidebar wrapper", async () => {
    sidebarWrapper.remove();
    document.documentElement.classList.add("aihelper-popup-pending");

    await load();
    window.AiHelperChat.initSidebar();

    expect(document.documentElement.classList.contains("aihelper-popup-pending")).toBe(false);
  });

  it("still sets up the page info when the sidebar element is missing", async () => {
    await load();
    window.AiHelperChat.initSidebar();

    expect(aiHelperMock.init_fold_flag).toHaveBeenCalled();
    expect(aiHelperMock.reload_chat).toHaveBeenCalled();
  });
});
