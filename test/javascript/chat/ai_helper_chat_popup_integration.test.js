import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";

const USER_ID = "7";
const OPEN_KEY = `aihelper-popup-open_${USER_ID}`;
const DRAFT_KEY = `aihelper-popup-draft_${USER_ID}`;
const LAYOUT_KEY = `aihelper-popup-layout_${USER_ID}`;

// The sidebar partial renders #aihelper-sidebar inside #content; initSidebar
// then moves it into #sidebar-wrapper. The chat form arrives later by XHR.
const PAGE_HTML = `
  <div id="content">
    <div id="aihelper-sidebar" data-chat-form-url="/ai_helper/chat_form" data-content-id="5"
         data-controller-name="issues" data-action-name="show" data-additional-info="{}">
      <div class="aihelper-header">
        <a href="#" id="aihelper-popup-open"></a><a href="#" id="aihelper-popup-close"></a>
      </div>
      <div id="aihelper-foldable-area">
        <div id="aihelper-chat-conversation"></div>
        <div id="aihelper-chat-form-area"></div>
      </div>
    </div>
  </div>
  <div id="sidebar"><div id="sidebar-wrapper"><h3>Other</h3></div></div>`;

describe("AiHelperChat and AiHelperChatPopup together (FR-005, FR-006, FR-012, FR-016)", () => {
  let aiHelper;

  beforeEach(async () => {
    localStorage.clear();
    sessionStorage.clear();
    document.body.innerHTML = PAGE_HTML;
    window.matchMedia = vi.fn(() => ({ matches: false, addEventListener: vi.fn() }));
    aiHelper = {
      userId: USER_ID,
      page_info: {},
      init_fold_flag: vi.fn(),
      reload_chat: vi.fn(),
      set_hamberger_menu: vi.fn(),
      // Like the real helper, run the form markup in place and let it initialize itself.
      innerHTMLwithScripts: vi.fn((element, html) => {
        element.innerHTML = html;
        window.AiHelperChat.initChatForm();
      }),
    };
    vi.stubGlobal("ai_helper", aiHelper);
    vi.stubGlobal(
      "XMLHttpRequest",
      vi.fn(function Xhr() {
        this.open = vi.fn();
        this.send = () => {
          this.status = 200;
          this.responseText = '<form id="ai_helper_chat_form"><textarea id="ai-helper-message-input"></textarea></form>';
          this.onload();
        };
      }),
    );
    await loadScript("assets/javascripts/chat/ai_helper_chat_popup_layout");
    await loadScript("assets/javascripts/chat/ai_helper_chat_popup");
    await loadScript("assets/javascripts/chat/ai_helper_chat");
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    delete window.matchMedia;
    delete window.AiHelperChat;
    delete window.AiHelperChatPopup;
    document.body.innerHTML = "";
    document.documentElement.className = "";
  });

  it("leaves the chat in the body as the popup when the tab was in popup mode, with page info and the restored draft", () => {
    sessionStorage.setItem(OPEN_KEY, "true");
    sessionStorage.setItem(DRAFT_KEY, "unsent text");
    localStorage.setItem(LAYOUT_KEY, JSON.stringify({ left: 10, top: 20, width: 300, height: 400 }));
    document.documentElement.classList.add("aihelper-popup-pending");
    const sidebar = document.getElementById("aihelper-sidebar");

    window.AiHelperChat.initSidebar();

    expect(sidebar.parentElement).toBe(document.body);
    expect(sidebar.classList.contains("aihelper-popup-mode")).toBe(true);
    expect(document.documentElement.classList.contains("aihelper-popup-pending")).toBe(false);
    expect(aiHelper.page_info).toMatchObject({ content_id: "5", controller_name: "issues", action_name: "show" });
    expect(document.getElementById("ai-helper-message-input").value).toBe("unsent text");
  });

  it("keeps the chat at the top of the sidebar when the tab was not in popup mode", () => {
    const sidebar = document.getElementById("aihelper-sidebar");

    window.AiHelperChat.initSidebar();

    const wrapper = document.getElementById("sidebar-wrapper");
    expect(sidebar.parentElement).toBe(wrapper);
    expect(wrapper.firstElementChild).toBe(sidebar);
    expect(document.getElementById("ai-helper-message-input").value).toBe("");
  });
});
