import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";

function createAiHelperDOM() {
  const container = document.createElement("div");

  // Chat conversation area
  const chatConversation = document.createElement("div");
  chatConversation.id = "aihelper-chat-conversation";
  container.appendChild(chatConversation);

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
  container.appendChild(interactiveOptions);

  // CSRF meta tag
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "test-csrf-token";
  document.head.appendChild(meta);

  document.body.appendChild(container);

  return {
    container,
    chatConversation,
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
    onload: null,
    onerror: null,
  };
  vi.stubGlobal("XMLHttpRequest", function () {
    return xhr;
  });
  return xhr;
}

describe("AiHelper history", () => {
  let dom;
  let helper;
  let xhr;

  beforeEach(async () => {
    await loadScript("assets/javascripts/chat/ai_helper");
    await loadScript("assets/javascripts/chat/ai_helper_history");
    dom = createAiHelperDOM();
    xhr = createXhrMock();
    window.ai_helper_urls = {
      reload: "/ai_helper/reload",
      history: "/ai_helper/history",
      clear: "/ai_helper/clear",
    };
    helper = window.ai_helper;
  });

  afterEach(() => {
    if (dom && dom.container && dom.container.parentNode) {
      dom.container.remove();
    }
    const meta = document.querySelector('meta[name="csrf-token"]');
    if (meta) {meta.remove();}
    delete window.ai_helper_urls;
    vi.unstubAllGlobals();
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
      if (documentClickListener) {document.removeEventListener("click", documentClickListener);}
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
