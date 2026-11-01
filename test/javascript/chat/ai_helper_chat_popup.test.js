import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";

const USER_ID = "7";
const LAYOUT_KEY = `aihelper-popup-layout_${USER_ID}`;
const OPEN_KEY = `aihelper-popup-open_${USER_ID}`;
const DRAFT_KEY = `aihelper-popup-draft_${USER_ID}`;
const FOLD_KEY = `aihelper-fold-flag_${USER_ID}`;

// Mirrors app/views/ai_helper/chat/_sidebar.html.erb (header, open/close
// links, foldable area, 8 resize handles as direct children of the sidebar)
// and the chat form rendered by ai_helper/chat/_chat_form.html.erb. The
// sidebar sits in #sidebar-wrapper exactly as AiHelperChat.initSidebar
// leaves it, so a test can assert a moved element was not already at its target.
const windowListeners = [];

const SIDEBAR_HTML = `
  <div id="aihelper-sidebar">
    <div class="aihelper-header">
      <span class="aihelper-hamburger"><span></span><span></span><span></span></span>
      <span class="aihelper-title">AI Helper</span>
      <a href="#" id="aihelper-popup-open" class="aihelper-popup-button icon-only"></a>
      <span class="aihelper-arrow-button">
        <span class="aihelper-arrow-container">
          <a href="#" class="aihelper-arrow down" id="aihelper-arrow-down"></a>
          <a href="#" class="aihelper-arrow left" id="aihelper-arrow-left" style="display: none"></a>
        </span>
      </span>
      <a href="#" id="aihelper-popup-close" class="aihelper-popup-button icon-only"></a>
      <div class="aihelper-dropdown-menu"><a href="#" id="aihelper-history-link">history</a></div>
    </div>
    <div id="aihelper-foldable-area">
      <div id="aihelper-chat-conversation"></div>
      <div id="aihelper-chat-form-area">
        <form id="ai_helper_chat_form"><textarea id="ai-helper-message-input"></textarea></form>
      </div>
    </div>
    ${["n", "s", "e", "w", "ne", "nw", "se", "sw"].map((e) => `<div class="aihelper-popup-resize" data-edge="${e}"></div>`).join("")}
  </div>`;

/**
 * Builds the page: #sidebar > #sidebar-wrapper > #aihelper-sidebar.
 * @returns {HTMLElement} the #aihelper-sidebar element
 */
function buildPage() {
  document.body.innerHTML = `<div id="sidebar"><div id="sidebar-wrapper"><h3>Other</h3>${SIDEBAR_HTML}</div></div>`;
  return document.getElementById("aihelper-sidebar");
}

/**
 * Makes getBoundingClientRect return a fixed rectangle (jsdom returns zeros).
 * @param {HTMLElement} element - Element to stub.
 * @param {{left: number, top: number, width: number, height: number}} rect - Rectangle to report.
 */
function stubRect(element, rect) {
  element.getBoundingClientRect = () => ({
    ...rect, right: rect.left + rect.width, bottom: rect.top + rect.height, x: rect.left, y: rect.top,
  });
}

/**
 * Sets the visible viewport size the popup is clamped to.
 * @param {number} width - Viewport width.
 * @param {number} height - Viewport height.
 */
function stubViewport(width, height) {
  Object.defineProperty(document.documentElement, "clientWidth", { configurable: true, value: width });
  Object.defineProperty(document.documentElement, "clientHeight", { configurable: true, value: height });
}

/**
 * Loads the script under test.
 * @returns {Promise<object>} the AiHelperChatPopup global
 */
async function load() {
  await loadScript("assets/javascripts/chat/ai_helper_chat_popup_layout");
  await loadScript("assets/javascripts/chat/ai_helper_chat_popup");
  return window.AiHelperChatPopup;
}

/**
 * Resets storage, stubs the globals the script reads and builds the page.
 * @returns {HTMLElement} the #aihelper-sidebar element
 */
function setupPage() {
  const originalAdd = window.addEventListener.bind(window);
  vi.spyOn(window, "addEventListener").mockImplementation((type, listener, options) => {
    windowListeners.push([type, listener, options]);
    originalAdd(type, listener, options);
  });
  localStorage.clear();
  sessionStorage.clear();
  vi.stubGlobal("ai_helper", { userId: USER_ID });
  stubViewport(1024, 768);
  const element = buildPage();
  stubRect(element, { left: 800, top: 100, width: 240, height: 600 });
  return element;
}

/** Undoes everything setupPage and the tests changed. */
function teardownPage() {
  // Window listeners added by init() would otherwise act on later pages.
  windowListeners.splice(0).forEach(([type, listener, options]) => window.removeEventListener(type, listener, options));
  vi.useRealTimers();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  delete window.AiHelperChatPopup;
  delete window.matchMedia;
  delete document.documentElement.clientWidth;
  delete document.documentElement.clientHeight;
  document.body.innerHTML = "";
  document.documentElement.className = "";
}

/**
 * Closes the popup and lets the close animation (FR-019) finish.
 * @param {object} popup - The AiHelperChatPopup global.
 */
function closeAndFinish(popup) {
  vi.useFakeTimers();
  popup.close();
  vi.advanceTimersByTime(200);
}

/**
 * Installs a controllable window.matchMedia (jsdom has none).
 * @param {boolean} matches - Initial value of the query's `matches`.
 * @returns {{query: object, change: Function, mediaQuery: Function}} helpers; `change(matches)` fires a change event
 */
function stubMatchMedia(matches) {
  const listeners = [];
  const query = {
    matches,
    addEventListener: (type, listener) => {
      if (type === "change") {
        listeners.push(listener);
      }
    },
  };
  const mediaQuery = vi.fn(() => query);
  window.matchMedia = mediaQuery;
  return {
    query,
    mediaQuery,
    change(next) {
      query.matches = next;
      listeners.forEach((listener) => listener({ matches: next }));
    },
  };
}

describe("AiHelperChatPopup layout selection", () => {
  const DEFAULT_LAYOUT = { left: 776, top: 124, width: 240, height: 600 };
  let sidebar;
  let popup;

  /**
   * Reads the layout the popup was opened with from the inline styles.
   * @returns {{left: number, top: number, width: number, height: number}} the layout
   */
  function applied() {
    return {
      left: parseFloat(sidebar.style.left),
      top: parseFloat(sidebar.style.top),
      width: parseFloat(sidebar.style.width),
      height: parseFloat(sidebar.style.height),
    };
  }

  beforeEach(async () => {
    sidebar = setupPage();
    stubMatchMedia(false);
    popup = await load();
    popup.init();
  });

  afterEach(teardownPage);

  it("opens with a saved valid layout without measuring the sidebar", () => {
    const saved = { left: 10, top: 20, width: 300, height: 400 };
    localStorage.setItem(LAYOUT_KEY, JSON.stringify(saved));
    sidebar.getBoundingClientRect = () => {
      throw new Error("must not measure when a layout is saved");
    };

    // The measurement for the animation start is the only one allowed.
    sidebar.getBoundingClientRect = () => ({ left: 800, top: 100 });
    popup.open();

    expect(applied()).toEqual(saved);
  });

  it("computes the default from the measured sidebar and saves it", () => {
    popup.open();

    expect(applied()).toEqual(DEFAULT_LAYOUT);
    expect(JSON.parse(localStorage.getItem(LAYOUT_KEY))).toEqual(DEFAULT_LAYOUT);
  });

  it("measures the expanded height when the sidebar chat is folded, and restores the fold", () => {
    const area = document.getElementById("aihelper-foldable-area");
    area.style.display = "none";
    sidebar.getBoundingClientRect = () => {
      const height = area.style.display === "none" ? 30 : 600;
      return { left: 800, top: 100, width: 240, height, right: 1040, bottom: 100 + height, x: 800, y: 100 };
    };

    popup.open();

    expect(JSON.parse(localStorage.getItem(LAYOUT_KEY)).height).toBe(600);
    expect(area.style.display).toBe("none");
  });

  it("does not save a default that has no size, and shows the minimum size instead", () => {
    stubRect(sidebar, { left: 0, top: 0, width: 0, height: 0 });

    popup.open();

    expect(localStorage.getItem(LAYOUT_KEY)).toBeNull();
    expect(applied()).toEqual({ left: 0, top: 24, width: 240, height: 240 });
  });

  it("uses the default and saves it again when the saved JSON is broken", () => {
    localStorage.setItem(LAYOUT_KEY, "{not json");

    popup.open();

    expect(applied()).toEqual(DEFAULT_LAYOUT);
    expect(JSON.parse(localStorage.getItem(LAYOUT_KEY))).toEqual(DEFAULT_LAYOUT);
  });

  it("does not catch errors other than a JSON SyntaxError", () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new DOMException("denied", "SecurityError");
    });

    expect(() => popup.open()).toThrow(/denied/);
  });

  it("rethrows a parse failure that is not a SyntaxError", () => {
    localStorage.setItem(LAYOUT_KEY, "{}");
    vi.spyOn(JSON, "parse").mockImplementation(() => {
      throw new TypeError("unexpected");
    });

    expect(() => popup.open()).toThrow(/unexpected/);
  });

  it.each([
    ["missing left", { top: 1, width: 300, height: 300 }],
    ["missing width", { left: 1, top: 1, height: 300 }],
    ["string number", { left: "1", top: 1, width: 300, height: 300 }],
    ["null value", { left: null, top: 1, width: 300, height: 300 }],
    ["zero width", { left: 1, top: 1, width: 0, height: 300 }],
    ["negative height", { left: 1, top: 1, width: 300, height: -5 }],
  ])("treats %s as invalid and uses the default", (_name, value) => {
    localStorage.setItem(LAYOUT_KEY, JSON.stringify(value));

    popup.open();

    expect(applied()).toEqual(DEFAULT_LAYOUT);
  });

  it.each([
    ["a JSON value that is not an object", "null"],
    ["a number that is not finite", '{"left":1e999,"top":1,"width":300,"height":300}'],
  ])("treats %s as invalid and uses the default", (_name, raw) => {
    localStorage.setItem(LAYOUT_KEY, raw);

    popup.open();

    expect(applied()).toEqual(DEFAULT_LAYOUT);
  });

  it("keeps layouts of different users apart", () => {
    localStorage.setItem("aihelper-popup-layout_8", JSON.stringify({ left: 1, top: 2, width: 300, height: 300 }));

    popup.open();

    expect(applied()).toEqual(DEFAULT_LAYOUT);
    expect(JSON.parse(localStorage.getItem("aihelper-popup-layout_8")).left).toBe(1);
  });

  it("shrinks an oversized saved layout to the viewport without saving the fitted value", () => {
    const saved = { left: 0, top: 0, width: 2000, height: 2000 };
    localStorage.setItem(LAYOUT_KEY, JSON.stringify(saved));

    popup.open();

    expect(applied()).toEqual({ left: 0, top: 0, width: 1024, height: 768 });
    expect(JSON.parse(localStorage.getItem(LAYOUT_KEY))).toEqual(saved);
  });
});

describe("AiHelperChatPopup open and close", () => {
  let sidebar;
  let popup;
  let media;

  /**
   * Gives an element a settable scrollTop and a fixed scrollHeight (jsdom
   * has no layout).
   * @param {HTMLElement} element - Element to stub.
   * @param {number} scrollHeight - Reported scrollHeight.
   */
  function stubScroll(element, scrollHeight) {
    let top = 0;
    Object.defineProperty(element, "scrollHeight", { configurable: true, value: scrollHeight });
    Object.defineProperty(element, "scrollTop", { configurable: true, get: () => top, set: (v) => { top = v; } });
  }

  beforeEach(async () => {
    sidebar = setupPage();
    media = stubMatchMedia(false);
    popup = await load();
    popup.init();
  });

  afterEach(teardownPage);

  it("open() moves the sidebar chat to the body and enters popup mode", () => {
    const wrapper = document.getElementById("sidebar-wrapper");
    expect(sidebar.parentElement).toBe(wrapper);

    popup.open();

    expect(sidebar.parentElement).toBe(document.body);
    expect(sidebar.classList.contains("aihelper-popup-mode")).toBe(true);
    expect(wrapper.contains(sidebar)).toBe(false);
  });

  it("open() adds only the chat element to the body, so nothing covers the page behind it", () => {
    const before = Array.from(document.body.children);

    popup.open();

    const added = Array.from(document.body.children).filter((child) => !before.includes(child));
    expect(added).toEqual([sidebar]);
  });

  it("open() records the open state for this tab and user", () => {
    popup.open();

    expect(sessionStorage.getItem(OPEN_KEY)).toBe("true");
    expect(localStorage.getItem(OPEN_KEY)).toBeNull();
  });

  it("open() uses the saved layout and measures the sidebar before moving it", () => {
    localStorage.setItem(LAYOUT_KEY, JSON.stringify({ left: 50, top: 60, width: 300, height: 400 }));
    const order = [];
    const measure = sidebar.getBoundingClientRect;
    sidebar.getBoundingClientRect = () => {
      order.push(sidebar.parentElement === document.body ? "after-move" : "before-move");
      return measure();
    };

    popup.open();

    expect(order).toEqual(["before-move"]);
    expect(sidebar.style.width).toBe("300px");
    expect(sidebar.style.height).toBe("400px");
  });

  it("open() fits a saved layout that no longer fits the viewport, without saving the fitted value", () => {
    const saved = { left: 900, top: 700, width: 300, height: 300 };
    localStorage.setItem(LAYOUT_KEY, JSON.stringify(saved));

    popup.open();

    expect(sidebar.style.left).toBe("724px");
    expect(sidebar.style.top).toBe("468px");
    expect(JSON.parse(localStorage.getItem(LAYOUT_KEY))).toEqual(saved);
  });

  it("open() saves the default layout when none is saved", () => {
    popup.open();

    expect(JSON.parse(localStorage.getItem(LAYOUT_KEY))).toEqual({ left: 776, top: 124, width: 240, height: 600 });
  });

  it("close() moves the chat back to the top of #sidebar-wrapper", () => {
    popup.open();
    expect(sidebar.parentElement).toBe(document.body);

    closeAndFinish(popup);

    const wrapper = document.getElementById("sidebar-wrapper");
    expect(sidebar.parentElement).toBe(wrapper);
    expect(wrapper.firstElementChild).toBe(sidebar);
    expect(sidebar.classList.contains("aihelper-popup-mode")).toBe(false);
    expect([sidebar.style.left, sidebar.style.top, sidebar.style.width, sidebar.style.height]).toEqual(["", "", "", ""]);
  });

  it("close() removes the open state and the saved draft but keeps the input value", () => {
    popup.open();
    sessionStorage.setItem(DRAFT_KEY, "draft");
    document.getElementById("ai-helper-message-input").value = "typed text";

    closeAndFinish(popup);

    expect(sessionStorage.getItem(OPEN_KEY)).toBeNull();
    expect(sessionStorage.getItem(DRAFT_KEY)).toBeNull();
    expect(document.getElementById("ai-helper-message-input").value).toBe("typed text");
  });

  it("keeps the unsent input text through open and close (FR-004)", () => {
    const input = document.getElementById("ai-helper-message-input");
    input.value = "line one\nline two";

    popup.open();
    expect(input.value).toBe("line one\nline two");
    closeAndFinish(popup);

    expect(input.value).toBe("line one\nline two");
  });

  it("moves the existing conversation element instead of cloning it", () => {
    const conversation = document.getElementById("aihelper-chat-conversation");
    conversation.dataset.marker = "same-instance";

    popup.open();

    expect(document.querySelectorAll("#aihelper-chat-conversation")).toHaveLength(1);
    expect(document.getElementById("aihelper-chat-conversation")).toBe(conversation);
    expect(document.querySelectorAll("#aihelper-sidebar")).toHaveLength(1);
  });

  it("keeps focus on the element that had it and scrolls the conversation to the end", () => {
    const input = document.getElementById("ai-helper-message-input");
    const conversation = document.getElementById("aihelper-chat-conversation");
    stubScroll(conversation, 500);
    input.focus();
    expect(document.activeElement).toBe(input);

    popup.open();
    expect(document.activeElement).toBe(input);
    expect(conversation.scrollTop).toBe(500);

    conversation.scrollTop = 0;
    closeAndFinish(popup);
    expect(document.activeElement).toBe(input);
    expect(conversation.scrollTop).toBe(500);
  });

  it("does not move focus when nothing inside the chat had it", () => {
    const outside = document.createElement("input");
    document.body.appendChild(outside);
    outside.focus();

    popup.open();

    expect(document.activeElement).toBe(outside);
  });

  it("never writes the sidebar fold state", () => {
    const setItem = vi.spyOn(Storage.prototype, "setItem");

    popup.open();
    closeAndFinish(popup);

    const keys = setItem.mock.calls.map((call) => call[0]);
    expect(keys).not.toContain(FOLD_KEY);
  });

  it("opens on a click on #aihelper-popup-open and closes on #aihelper-popup-close", () => {
    const openClick = new MouseEvent("click", { bubbles: true, cancelable: true });
    document.getElementById("aihelper-popup-open").dispatchEvent(openClick);
    expect(openClick.defaultPrevented).toBe(true);
    expect(sidebar.parentElement).toBe(document.body);

    const closeClick = new MouseEvent("click", { bubbles: true, cancelable: true });
    vi.useFakeTimers();
    document.getElementById("aihelper-popup-close").dispatchEvent(closeClick);
    vi.advanceTimersByTime(200);
    expect(closeClick.defaultPrevented).toBe(true);
    expect(sidebar.parentElement).toBe(document.getElementById("sidebar-wrapper"));
  });

  it("ignores a second open() while the popup is already open", () => {
    popup.open();
    const setItem = vi.spyOn(Storage.prototype, "setItem");
    sidebar.style.left = "123px";

    popup.open();

    expect(sidebar.parentElement).toBe(document.body);
    expect(sidebar.style.left).toBe("123px");
    expect(setItem).not.toHaveBeenCalled();
  });

  it("ignores close() when the popup is not open", () => {
    const wrapper = document.getElementById("sidebar-wrapper");
    wrapper.removeChild(sidebar);
    wrapper.appendChild(sidebar);

    closeAndFinish(popup);

    expect(wrapper.lastElementChild).toBe(sidebar);
  });

  it("does not open when the narrow-screen query matches", () => {
    media.query.matches = true;

    popup.open();

    expect(sidebar.parentElement).toBe(document.getElementById("sidebar-wrapper"));
    expect(sessionStorage.getItem(OPEN_KEY)).toBeNull();
  });

  it("does not save the open state when showing the popup fails", () => {
    sidebar.getBoundingClientRect = () => {
      throw new Error("no box");
    };

    expect(() => popup.open()).toThrow(/no box/);

    expect(sessionStorage.getItem(OPEN_KEY)).toBeNull();
  });

  it("hands the focus to the close button when the open button had it, and back on close", () => {
    const openButton = document.getElementById("aihelper-popup-open");
    const closeButton = document.getElementById("aihelper-popup-close");
    openButton.focus();
    expect(document.activeElement).toBe(openButton);

    popup.open();
    expect(document.activeElement).toBe(closeButton);

    closeAndFinish(popup);
    expect(document.activeElement).toBe(openButton);
  });

  it("scrolls the conversation after the popup has its final size", () => {
    const conversation = document.getElementById("aihelper-chat-conversation");
    const heightWhenScrolled = [];
    Object.defineProperty(conversation, "scrollHeight", { configurable: true, value: 500 });
    Object.defineProperty(conversation, "scrollTop", {
      configurable: true,
      get: () => 0,
      set: () => {
        heightWhenScrolled.push(sidebar.style.height);
      },
    });
    localStorage.setItem(LAYOUT_KEY, JSON.stringify({ left: 50, top: 60, width: 300, height: 400 }));

    popup.open();

    expect(heightWhenScrolled).toEqual(["400px"]);
  });

  it("does not call focus when nothing inside the chat had it", () => {
    const outside = document.createElement("input");
    document.body.appendChild(outside);
    outside.focus();
    const focus = vi.spyOn(outside, "focus");

    popup.open();

    expect(focus).not.toHaveBeenCalled();
  });

  it("init() removes aihelper-popup-pending even when a control is missing", () => {
    teardownPage();
    setupPage();
    stubMatchMedia(false);
    document.documentElement.classList.add("aihelper-popup-pending");
    document.getElementById("aihelper-popup-close").remove();

    expect(() => window.AiHelperChatPopup).not.toThrow();
    return load().then((fresh) => {
      expect(() => fresh.init()).toThrow(/#aihelper-popup-close not found/);
      expect(document.documentElement.classList.contains("aihelper-popup-pending")).toBe(false);
    });
  });
});

describe("AiHelperChatPopup open animation (FR-018)", () => {
  let sidebar;
  let popup;

  beforeEach(async () => {
    sidebar = setupPage();
    stubMatchMedia(false);
    popup = await load();
    popup.init();
    vi.useFakeTimers();
  });

  afterEach(teardownPage);

  it("starts at the sidebar position and ends at the layout after about 200ms", () => {
    localStorage.setItem(LAYOUT_KEY, JSON.stringify({ left: 300, top: 50, width: 320, height: 420 }));

    popup.open();

    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(true);
    expect(sidebar.style.left).toBe("300px");
    expect(sidebar.style.top).toBe("50px");

    vi.advanceTimersByTime(199);
    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(true);
    vi.advanceTimersByTime(1);
    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(false);
  });

  it("begins the move from the position the chat had in the sidebar", () => {
    // offsetWidth is read as the reflow point between the start and end positions.
    let leftAtReflow = null;
    let topAtReflow = null;
    Object.defineProperty(sidebar, "offsetWidth", {
      configurable: true,
      get: () => {
        leftAtReflow = sidebar.style.left;
        topAtReflow = sidebar.style.top;
        return 0;
      },
    });
    localStorage.setItem(LAYOUT_KEY, JSON.stringify({ left: 300, top: 50, width: 320, height: 420 }));

    popup.open();

    expect(leftAtReflow).toBe("800px");
    expect(topAtReflow).toBe("100px");
    expect(sidebar.style.left).toBe("300px");
    expect(sidebar.style.top).toBe("50px");
  });

  it("animates when opening toward a default layout too", () => {
    popup.open();

    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(true);
  });

  it("an older animation timer does not end a newer animation", () => {
    popup.open();
    vi.advanceTimersByTime(100);
    popup.close();
    popup.open();
    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(true);

    vi.advanceTimersByTime(100);

    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(true);
    vi.advanceTimersByTime(100);
    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(false);
  });

  it("close() replaces the open animation with the close animation", () => {
    popup.open();
    vi.advanceTimersByTime(100);

    popup.close();
    vi.advanceTimersByTime(100);
    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(true);
    vi.advanceTimersByTime(100);

    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(false);
    expect(sidebar.parentElement).toBe(document.getElementById("sidebar-wrapper"));
  });
});

describe("AiHelperChatPopup close animation (FR-019)", () => {
  let sidebar;
  let wrapper;
  let popup;
  let media;

  beforeEach(async () => {
    sidebar = setupPage();
    wrapper = document.getElementById("sidebar-wrapper");
    // The sidebar slot: where the chat lands when it returns to the top of #sidebar-wrapper.
    stubRect(wrapper, { left: 800, top: 60, width: 240, height: 700 });
    media = stubMatchMedia(false);
    popup = await load();
    popup.init();
    vi.useFakeTimers();
    localStorage.setItem(LAYOUT_KEY, JSON.stringify({ left: 300, top: 50, width: 320, height: 420 }));
    popup.open();
    vi.advanceTimersByTime(200);
  });

  afterEach(teardownPage);

  it("close() animates the position and size back to the sidebar slot and stays in the body meanwhile", () => {
    expect(sidebar.parentElement).toBe(document.body);
    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(false);

    popup.close();

    expect(sidebar.parentElement).toBe(document.body);
    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(true);
    expect([sidebar.style.left, sidebar.style.top, sidebar.style.width, sidebar.style.height])
      .toEqual(["800px", "60px", "240px", "600px"]);
  });

  it("returns the chat to the top of #sidebar-wrapper after about 200ms and clears the popup styles", () => {
    popup.close();

    vi.advanceTimersByTime(199);
    expect(sidebar.parentElement).toBe(document.body);
    vi.advanceTimersByTime(1);

    expect(sidebar.parentElement).toBe(wrapper);
    expect(wrapper.firstElementChild).toBe(sidebar);
    expect(sidebar.classList.contains("aihelper-popup-mode")).toBe(false);
    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(false);
    expect([sidebar.style.left, sidebar.style.top, sidebar.style.width, sidebar.style.height]).toEqual(["", "", "", ""]);
  });

  it("starts the transition from the popup layout", () => {
    // offsetWidth is read as the reflow point between the start and end values.
    let leftAtReflow = null;
    let widthAtReflow = null;
    Object.defineProperty(sidebar, "offsetWidth", {
      configurable: true,
      get: () => {
        leftAtReflow = sidebar.style.left;
        widthAtReflow = sidebar.style.width;
        return 0;
      },
    });

    popup.close();

    expect(leftAtReflow).toBe("300px");
    expect(widthAtReflow).toBe("320px");
  });

  it("removes the open state and the draft when close() is called, without waiting for the animation", () => {
    sessionStorage.setItem(DRAFT_KEY, "draft");

    popup.close();

    expect(sessionStorage.getItem(OPEN_KEY)).toBeNull();
    expect(sessionStorage.getItem(DRAFT_KEY)).toBeNull();
    expect(sidebar.parentElement).toBe(document.body);
  });

  it("ignores a second close() during the animation and does not restart its timer", () => {
    popup.close();
    vi.advanceTimersByTime(100);

    popup.close();
    vi.advanceTimersByTime(100);

    expect(sidebar.parentElement).toBe(wrapper);
  });

  it("returns at once, without animation, when the screen becomes narrow during the animation", () => {
    popup.close();
    vi.advanceTimersByTime(100);

    media.change(true);

    expect(sidebar.parentElement).toBe(wrapper);
    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(false);
    expect(sidebar.style.left).toBe("");
  });

  it("an older close timer does not move a popup that was opened again", () => {
    popup.close();
    vi.advanceTimersByTime(100);
    media.change(true);
    media.change(false);
    popup.open();
    expect(sidebar.parentElement).toBe(document.body);

    vi.advanceTimersByTime(300);

    expect(sidebar.parentElement).toBe(document.body);
    expect(sidebar.classList.contains("aihelper-popup-mode")).toBe(true);
  });

  it("a narrow-screen close does not animate", () => {
    media.change(true);

    expect(sidebar.parentElement).toBe(wrapper);
    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(false);
  });

  it("does not re-apply the popup layout on a window resize during the animation", () => {
    popup.close();
    vi.advanceTimersByTime(100);
    stubViewport(380, 300);

    window.dispatchEvent(new Event("resize"));

    expect([sidebar.style.left, sidebar.style.top, sidebar.style.width, sidebar.style.height])
      .toEqual(["800px", "60px", "240px", "600px"]);
    vi.advanceTimersByTime(100);
    expect(sidebar.parentElement).toBe(wrapper);
  });

  it("keeps the input text and the conversation element through the animation", () => {
    const conversation = document.getElementById("aihelper-chat-conversation");
    document.getElementById("ai-helper-message-input").value = "typed text";

    popup.close();
    vi.advanceTimersByTime(200);

    expect(document.getElementById("ai-helper-message-input").value).toBe("typed text");
    expect(document.getElementById("aihelper-chat-conversation")).toBe(conversation);
  });
});

describe("AiHelperChatPopup narrow screens (FR-001)", () => {
  let sidebar;
  let popup;
  let media;

  beforeEach(async () => {
    sidebar = setupPage();
  });

  afterEach(teardownPage);

  /**
   * Loads and initializes the script with the given query state.
   * @param {boolean} matches - Whether the narrow query matches at init.
   */
  async function start(matches) {
    media = stubMatchMedia(matches);
    popup = await load();
    popup.init();
  }

  it("asks for the 899px breakpoint Redmine uses for the flyout menu", async () => {
    await start(false);

    expect(media.mediaQuery).toHaveBeenCalledWith("(max-width: 899px)");
  });

  it("init() on a narrow screen leaves the chat in the sidebar and keeps the saved open state", async () => {
    sessionStorage.setItem(OPEN_KEY, "true");

    await start(true);

    expect(sidebar.parentElement).toBe(document.getElementById("sidebar-wrapper"));
    expect(sessionStorage.getItem(OPEN_KEY)).toBe("true");
  });

  it("returns the chat to the sidebar when the screen becomes narrow, keeping the open state", async () => {
    await start(false);
    popup.open();
    expect(sidebar.parentElement).toBe(document.body);

    media.change(true);

    expect(sidebar.parentElement).toBe(document.getElementById("sidebar-wrapper"));
    expect(sidebar.classList.contains("aihelper-popup-mode")).toBe(false);
    expect(sessionStorage.getItem(OPEN_KEY)).toBe("true");
  });

  it("shows the popup again, without animation, when the screen is wide again and the state is open", async () => {
    vi.useFakeTimers();
    await start(false);
    popup.open();
    vi.advanceTimersByTime(300);
    media.change(true);

    media.change(false);

    expect(sidebar.parentElement).toBe(document.body);
    expect(sidebar.classList.contains("aihelper-popup-mode")).toBe(true);
    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(false);
  });

  it("stays in the sidebar when the screen is wide again but the popup was never opened", async () => {
    await start(true);

    media.change(false);

    expect(sidebar.parentElement).toBe(document.getElementById("sidebar-wrapper"));
  });

  it("ignores a change event that does not change the mode", async () => {
    await start(false);
    popup.open();
    sidebar.style.left = "5px";

    media.change(false);

    expect(sidebar.parentElement).toBe(document.body);
    expect(sidebar.style.left).toBe("5px");
  });
});

describe("AiHelperChatPopup restore after page navigation (FR-012, FR-016)", () => {
  let sidebar;
  let popup;

  /**
   * Loads the script and runs init() like AiHelperChat.initSidebar does.
   * @param {boolean} [narrow] - Whether the narrow-screen query matches.
   */
  async function start(narrow = false) {
    stubMatchMedia(narrow);
    popup = await load();
    popup.init();
  }

  /**
   * Returns the chat's message input.
   * @returns {HTMLTextAreaElement} the textarea
   */
  function input() {
    return document.getElementById("ai-helper-message-input");
  }

  beforeEach(() => {
    sidebar = setupPage();
  });

  afterEach(teardownPage);

  it("init() shows the popup without animation when this tab was in popup mode", async () => {
    sessionStorage.setItem(OPEN_KEY, "true");
    localStorage.setItem(LAYOUT_KEY, JSON.stringify({ left: 120, top: 80, width: 320, height: 420 }));
    expect(sidebar.parentElement).toBe(document.getElementById("sidebar-wrapper"));

    await start();

    expect(sidebar.parentElement).toBe(document.body);
    expect(sidebar.classList.contains("aihelper-popup-mode")).toBe(true);
    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(false);
    expect([sidebar.style.left, sidebar.style.top, sidebar.style.width, sidebar.style.height]).toEqual(["120px", "80px", "320px", "420px"]);
  });

  it("init() keeps the chat in the sidebar when the tab was not in popup mode", async () => {
    await start();

    expect(sidebar.parentElement).toBe(document.getElementById("sidebar-wrapper"));
    expect(sidebar.classList.contains("aihelper-popup-mode")).toBe(false);
  });

  it("init() removes aihelper-popup-pending from <html> in both cases", async () => {
    document.documentElement.classList.add("aihelper-popup-pending");
    sessionStorage.setItem(OPEN_KEY, "true");
    await start();
    expect(document.documentElement.classList.contains("aihelper-popup-pending")).toBe(false);

    teardownPage();
    sidebar = setupPage();
    document.documentElement.classList.add("aihelper-popup-pending");
    await start();
    expect(document.documentElement.classList.contains("aihelper-popup-pending")).toBe(false);
  });

  it("init() on a narrow screen removes aihelper-popup-pending and keeps the chat in the sidebar", async () => {
    document.documentElement.classList.add("aihelper-popup-pending");
    sessionStorage.setItem(OPEN_KEY, "true");

    await start(true);

    expect(document.documentElement.classList.contains("aihelper-popup-pending")).toBe(false);
    expect(sidebar.parentElement).toBe(document.getElementById("sidebar-wrapper"));
  });

  it("pagehide saves the typed text while the tab is in popup mode", async () => {
    sessionStorage.setItem(OPEN_KEY, "true");
    await start();
    input().value = "half written\nmessage";

    window.dispatchEvent(new Event("pagehide"));

    expect(sessionStorage.getItem(DRAFT_KEY)).toBe("half written\nmessage");
  });

  it("pagehide removes the saved draft when the tab is not in popup mode, and never saves sidebar input", async () => {
    sessionStorage.setItem(DRAFT_KEY, "old draft");
    await start();
    input().value = "typed in the sidebar";

    window.dispatchEvent(new Event("pagehide"));

    expect(sessionStorage.getItem(DRAFT_KEY)).toBeNull();
  });

  it("pagehide keeps the saved draft when the chat form has not loaded yet", async () => {
    sessionStorage.setItem(OPEN_KEY, "true");
    sessionStorage.setItem(DRAFT_KEY, "saved on the previous page");
    await start();
    document.getElementById("ai_helper_chat_form").remove();
    expect(input()).toBeNull();

    window.dispatchEvent(new Event("pagehide"));

    expect(sessionStorage.getItem(DRAFT_KEY)).toBe("saved on the previous page");
  });

  it("pagehide removes the draft when the input is empty, so a sent message is not carried over", async () => {
    sessionStorage.setItem(OPEN_KEY, "true");
    sessionStorage.setItem(DRAFT_KEY, "message that was sent afterwards");
    await start();
    input().value = "";

    window.dispatchEvent(new Event("pagehide"));

    expect(sessionStorage.getItem(DRAFT_KEY)).toBeNull();
  });

  it("pagehide saves a draft typed on a narrow screen while the open state is kept", async () => {
    sessionStorage.setItem(OPEN_KEY, "true");
    await start(true);
    input().value = "typed in the flyout";

    window.dispatchEvent(new Event("pagehide"));

    expect(sessionStorage.getItem(DRAFT_KEY)).toBe("typed in the flyout");
  });

  it("restoreDraft() fills an empty input while the tab is in popup mode", async () => {
    sessionStorage.setItem(OPEN_KEY, "true");
    sessionStorage.setItem(DRAFT_KEY, "carried over");
    await start();

    popup.restoreDraft();

    expect(input().value).toBe("carried over");
  });

  it("restoreDraft() does not overwrite text that is already in the input", async () => {
    sessionStorage.setItem(OPEN_KEY, "true");
    sessionStorage.setItem(DRAFT_KEY, "carried over");
    await start();
    input().value = "typed already";

    popup.restoreDraft();

    expect(input().value).toBe("typed already");
  });

  it("restoreDraft() does nothing when the tab is not in popup mode", async () => {
    sessionStorage.setItem(DRAFT_KEY, "stale");
    await start();

    popup.restoreDraft();

    expect(input().value).toBe("");
  });

  it("restoreDraft() does nothing without a saved draft", async () => {
    sessionStorage.setItem(OPEN_KEY, "true");
    await start();

    popup.restoreDraft();

    expect(input().value).toBe("");
  });

  it("restoreDraft() throws when the chat form renders no input", async () => {
    sessionStorage.setItem(OPEN_KEY, "true");
    sessionStorage.setItem(DRAFT_KEY, "carried over");
    await start();
    document.getElementById("ai_helper_chat_form").remove();

    expect(() => popup.restoreDraft()).toThrow(/#ai-helper-message-input not found/);
  });

  it("restoreDraft() sets the text as a value, never as HTML", async () => {
    const payload = "<img src=x onerror=alert(1)><b>bold</b>";
    sessionStorage.setItem(OPEN_KEY, "true");
    sessionStorage.setItem(DRAFT_KEY, payload);
    await start();

    popup.restoreDraft();

    expect(input().value).toBe(payload);
    expect(input().children).toHaveLength(0);
    expect(input().textContent).toBe("");
    expect(document.querySelectorAll("img, b")).toHaveLength(0);
  });

  it("keeps the state of different users apart", async () => {
    sessionStorage.setItem("aihelper-popup-open_8", "true");
    sessionStorage.setItem("aihelper-popup-draft_8", "someone else");
    await start();

    popup.restoreDraft();

    expect(sidebar.parentElement).toBe(document.getElementById("sidebar-wrapper"));
    expect(input().value).toBe("");
  });
});

describe("AiHelperChatPopup pageshow from the back/forward cache (R-010)", () => {
  let sidebar;
  let popup;

  /**
   * Fires pageshow with the given persisted flag.
   * @param {boolean} persisted - Whether the page came from the bfcache.
   */
  function pageshow(persisted) {
    const event = new Event("pageshow");
    Object.defineProperty(event, "persisted", { value: persisted });
    window.dispatchEvent(event);
  }

  beforeEach(async () => {
    sidebar = setupPage();
    stubMatchMedia(false);
    popup = await load();
    popup.init();
  });

  afterEach(teardownPage);

  it("closes a popup whose open state was removed while the page was cached", () => {
    popup.open();
    sessionStorage.removeItem(OPEN_KEY);

    pageshow(true);

    expect(sidebar.parentElement).toBe(document.getElementById("sidebar-wrapper"));
  });

  it("opens the popup when the open state was set while the page was cached", () => {
    sessionStorage.setItem(OPEN_KEY, "true");

    pageshow(true);

    expect(sidebar.parentElement).toBe(document.body);
    expect(sidebar.classList.contains("aihelper-popup-animating")).toBe(false);
  });

  it("does nothing for a normal page show", () => {
    sessionStorage.setItem(OPEN_KEY, "true");

    pageshow(false);

    expect(sidebar.parentElement).toBe(document.getElementById("sidebar-wrapper"));
  });

  it("shows the saved layout again when the cached page comes back after the layout changed", () => {
    localStorage.setItem(LAYOUT_KEY, JSON.stringify({ left: 100, top: 100, width: 300, height: 300 }));
    popup.open();
    localStorage.setItem(LAYOUT_KEY, JSON.stringify({ left: 200, top: 150, width: 320, height: 330 }));

    pageshow(true);

    expect([sidebar.style.left, sidebar.style.top, sidebar.style.width, sidebar.style.height]).toEqual(["200px", "150px", "320px", "330px"]);
  });

  it("takes the draft from storage when the cached page comes back in popup mode", () => {
    const input = document.getElementById("ai-helper-message-input");
    sessionStorage.setItem(OPEN_KEY, "true");
    popup.open();
    input.value = "x";
    sessionStorage.setItem(DRAFT_KEY, "xy");

    pageshow(true);
    expect(input.value).toBe("xy");

    sessionStorage.removeItem(DRAFT_KEY);
    pageshow(true);
    expect(input.value).toBe("");
  });

  it("leaves the input alone when the cached page comes back in sidebar mode", () => {
    const input = document.getElementById("ai-helper-message-input");
    input.value = "typed in the sidebar";
    sessionStorage.setItem(DRAFT_KEY, "stale");

    pageshow(true);

    expect(input.value).toBe("typed in the sidebar");
  });

  it("leaves the draft alone when the cached page has no chat form yet", () => {
    sessionStorage.setItem(OPEN_KEY, "true");
    popup.open();
    document.getElementById("ai_helper_chat_form").remove();

    expect(() => pageshow(true)).not.toThrow();
  });
});

describe("AiHelperChatPopup drag and resize (FR-007, FR-008, FR-009)", () => {
  const START = { left: 100, top: 100, width: 300, height: 300 };
  let sidebar;
  let popup;
  let header;

  /**
   * Dispatches a pointer event. jsdom has no PointerEvent, so a MouseEvent
   * carries the pointer fields the script reads.
   * @param {EventTarget} target - Element the event is dispatched on.
   * @param {string} type - pointerdown, pointermove, pointerup or pointercancel.
   * @param {{x?: number, y?: number, id?: number, button?: number}} [fields] - Pointer fields.
   * @returns {Event} the dispatched event
   */
  function pointer(target, type, { x = 0, y = 0, id = 1, button = 0 } = {}) {
    const event = new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, button });
    Object.defineProperty(event, "pointerId", { value: id });
    target.dispatchEvent(event);
    return event;
  }

  /**
   * Drags `target` from (0, 0) by (dx, dy) and releases.
   * @param {HTMLElement} target - Element to press on.
   * @param {number} dx - Horizontal movement.
   * @param {number} dy - Vertical movement.
   */
  function drag(target, dx, dy) {
    pointer(target, "pointerdown", { x: 0, y: 0 });
    pointer(target, "pointermove", { x: dx, y: dy });
    pointer(target, "pointerup", { x: dx, y: dy });
  }

  /**
   * Reads the applied layout from the inline styles.
   * @returns {{left: number, top: number, width: number, height: number}} the layout
   */
  function applied() {
    return {
      left: parseFloat(sidebar.style.left),
      top: parseFloat(sidebar.style.top),
      width: parseFloat(sidebar.style.width),
      height: parseFloat(sidebar.style.height),
    };
  }

  /**
   * Returns the resize handle for an edge.
   * @param {string} edge - n, s, e, w, ne, nw, se or sw.
   * @returns {HTMLElement} the handle
   */
  function handle(edge) {
    return sidebar.querySelector(`.aihelper-popup-resize[data-edge="${edge}"]`);
  }

  beforeEach(async () => {
    sidebar = setupPage();
    stubMatchMedia(false);
    Element.prototype.setPointerCapture = vi.fn();
    Element.prototype.releasePointerCapture = vi.fn();
    localStorage.setItem(LAYOUT_KEY, JSON.stringify(START));
    popup = await load();
    popup.init();
    popup.open();
    header = sidebar.querySelector(".aihelper-header");
  });

  afterEach(() => {
    delete Element.prototype.setPointerCapture;
    delete Element.prototype.releasePointerCapture;
    teardownPage();
  });

  describe("moving", () => {
    it("moves by the pointer movement when the header is dragged", () => {
      drag(header, 40, -30);

      expect(applied()).toEqual({ left: 140, top: 70, width: 300, height: 300 });
    });

    it("moves while the pointer moves and saves once on release", () => {
      const setItem = vi.spyOn(Storage.prototype, "setItem");
      pointer(header, "pointerdown", { x: 0, y: 0 });

      pointer(header, "pointermove", { x: 10, y: 10 });
      pointer(header, "pointermove", { x: 20, y: 20 });
      expect(applied().left).toBe(120);
      expect(setItem).not.toHaveBeenCalled();

      pointer(header, "pointerup", { x: 20, y: 20 });
      const saves = setItem.mock.calls.filter((call) => call[0] === LAYOUT_KEY);
      expect(saves).toHaveLength(1);
      expect(JSON.parse(saves[0][1])).toEqual({ left: 120, top: 120, width: 300, height: 300 });
    });

    it.each([
      { edge: "left", dx: -500, dy: 0, expected: { left: 0, top: 100 } },
      { edge: "top", dx: 0, dy: -500, expected: { left: 100, top: 0 } },
      { edge: "right", dx: 900, dy: 0, expected: { left: 724, top: 100 } },
      { edge: "bottom", dx: 0, dy: 900, expected: { left: 100, top: 468 } },
    ])("cannot be moved past the $edge edge of the viewport", ({ dx, dy, expected }) => {
      drag(header, dx, dy);

      expect(applied()).toMatchObject(expected);
    });

    it.each(["a", ".aihelper-hamburger", ".aihelper-dropdown-menu"])("does not start on %s", (selector) => {
      const target = sidebar.querySelector(`.aihelper-header ${selector}`);

      drag(target, 50, 50);

      expect(applied()).toEqual(START);
    });

    it("does not start on a child of an excluded element", () => {
      const child = sidebar.querySelector(".aihelper-hamburger span");

      drag(child, 50, 50);

      expect(applied()).toEqual(START);
    });

    it("does not start on the popup close link", () => {
      drag(document.getElementById("aihelper-popup-close"), 50, 50);

      expect(applied()).toEqual(START);
    });

    it("does not start with a button other than the main one", () => {
      pointer(header, "pointerdown", { x: 0, y: 0, button: 2 });
      pointer(header, "pointermove", { x: 50, y: 50 });
      pointer(header, "pointerup", { x: 50, y: 50 });

      expect(applied()).toEqual(START);
    });

    it("captures the pointer on press and ends on pointerup and on pointercancel", () => {
      pointer(header, "pointerdown", { x: 0, y: 0, id: 5 });
      expect(Element.prototype.setPointerCapture).toHaveBeenCalledWith(5);

      pointer(header, "pointercancel", { x: 0, y: 0, id: 5 });
      pointer(header, "pointermove", { x: 50, y: 50, id: 5 });
      expect(applied().left).toBe(100);

      pointer(header, "pointerdown", { x: 0, y: 0, id: 6 });
      pointer(header, "pointerup", { x: 0, y: 0, id: 6 });
      pointer(header, "pointermove", { x: 50, y: 50, id: 6 });
      expect(applied().left).toBe(100);
    });

    it("ignores moves from a different pointer than the one that started the drag", () => {
      pointer(header, "pointerdown", { x: 0, y: 0, id: 1 });

      pointer(header, "pointermove", { x: 50, y: 50, id: 2 });

      expect(applied().left).toBe(100);
    });

    it("does not end the drag, or save, when a different pointer is released", () => {
      const setItem = vi.spyOn(Storage.prototype, "setItem");
      pointer(header, "pointerdown", { x: 0, y: 0, id: 1 });

      pointer(header, "pointerup", { x: 0, y: 0, id: 2 });
      pointer(header, "pointermove", { x: 10, y: 10, id: 1 });

      expect(setItem).not.toHaveBeenCalled();
      expect(applied().left).toBe(110);
    });

    it("ignores a second pointerdown while a drag is in progress", () => {
      pointer(header, "pointerdown", { x: 0, y: 0, id: 1 });
      pointer(header, "pointerdown", { x: 30, y: 30, id: 2 });

      pointer(header, "pointermove", { x: 10, y: 10, id: 1 });

      expect(applied().left).toBe(110);
    });

    it("does not start while the chat is in the sidebar", () => {
      closeAndFinish(popup);
      sidebar.style.left = "100px";
      sidebar.style.top = "100px";

      drag(header, 50, 50);

      expect(sidebar.style.left).toBe("100px");
      expect(localStorage.getItem(LAYOUT_KEY)).toBe(JSON.stringify(START));
    });

    it("prevents text selection and scrolling by cancelling the press", () => {
      const event = pointer(header, "pointerdown", { x: 0, y: 0 });

      expect(event.defaultPrevented).toBe(true);
    });

    it("drops a drag in progress when the popup is closed, and saves nothing for it", () => {
      pointer(header, "pointerdown", { x: 0, y: 0 });
      pointer(header, "pointermove", { x: 40, y: 40 });
      closeAndFinish(popup);
      const before = localStorage.getItem(LAYOUT_KEY);

      pointer(header, "pointermove", { x: 80, y: 80 });
      pointer(header, "pointerup", { x: 80, y: 80 });

      expect(localStorage.getItem(LAYOUT_KEY)).toBe(before);
    });
  });

  describe("what is saved", () => {
    it("saves nothing for a press and release without movement", () => {
      const setItem = vi.spyOn(Storage.prototype, "setItem");

      pointer(header, "pointerdown", { x: 0, y: 0 });
      pointer(header, "pointerup", { x: 0, y: 0 });

      expect(setItem).not.toHaveBeenCalled();
    });

    it("does not overwrite the saved size with the fitted size when the header is moved in a small window", () => {
      localStorage.setItem(LAYOUT_KEY, JSON.stringify({ left: 100, top: 100, width: 900, height: 700 }));
      closeAndFinish(popup);
      popup.open();
      stubViewport(500, 400);
      window.dispatchEvent(new Event("resize"));
      expect(applied()).toMatchObject({ width: 500, height: 400 });

      drag(header, 0, 0);
      expect(JSON.parse(localStorage.getItem(LAYOUT_KEY))).toMatchObject({ width: 900, height: 700 });

      drag(header, 10, 0);
      expect(JSON.parse(localStorage.getItem(LAYOUT_KEY))).toMatchObject({ width: 900, height: 700 });
    });

    it("keeps the saved height when only the width is resized in a small window", () => {
      localStorage.setItem(LAYOUT_KEY, JSON.stringify({ left: 0, top: 0, width: 900, height: 700 }));
      closeAndFinish(popup);
      popup.open();
      stubViewport(500, 400);
      window.dispatchEvent(new Event("resize"));

      drag(handle("e"), -10, 0);

      expect(JSON.parse(localStorage.getItem(LAYOUT_KEY))).toMatchObject({ width: 490, height: 700 });
    });

    it("shows the layout from before the drag and saves nothing on pointercancel", () => {
      const before = localStorage.getItem(LAYOUT_KEY);
      const setItem = vi.spyOn(Storage.prototype, "setItem");
      pointer(header, "pointerdown", { x: 0, y: 0, id: 5 });
      pointer(header, "pointermove", { x: 50, y: 50, id: 5 });
      expect(applied().left).toBe(150);

      pointer(header, "pointercancel", { x: 50, y: 50, id: 5 });

      expect(applied()).toEqual(START);
      expect(setItem).not.toHaveBeenCalled();
      expect(localStorage.getItem(LAYOUT_KEY)).toBe(before);
    });

    it("abandons the drag when the pointer capture is lost, without saving", () => {
      const setItem = vi.spyOn(Storage.prototype, "setItem");
      pointer(header, "pointerdown", { x: 0, y: 0, id: 5 });
      pointer(header, "pointermove", { x: 50, y: 50, id: 5 });

      pointer(header, "lostpointercapture", { id: 5 });
      pointer(header, "pointermove", { x: 90, y: 90, id: 5 });

      expect(applied()).toEqual(START);
      expect(setItem).not.toHaveBeenCalled();
    });

    it("does not treat the capture release that follows pointerup as a cancel", () => {
      drag(header, 40, 0);

      pointer(header, "lostpointercapture", { x: 40, y: 0 });

      expect(applied().left).toBe(140);
    });

    it("abandons a drag when the window is resized, so a stale start cannot leave the viewport", () => {
      pointer(handle("w"), "pointerdown", { x: 0, y: 0 });
      stubViewport(500, 768);
      window.dispatchEvent(new Event("resize"));
      const fitted = applied();

      pointer(handle("w"), "pointermove", { x: -5, y: 0 });

      expect(applied()).toEqual(fitted);
    });

    it("does not start when the press lands on the icon inside the close link", () => {
      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      document.getElementById("aihelper-popup-close").appendChild(svg);

      drag(svg, 50, 50);

      expect(applied()).toEqual(START);
    });
  });

  describe("resizing", () => {
    it.each([
      { edge: "e", dx: 40, dy: 0, expected: { left: 100, top: 100, width: 340, height: 300 } },
      { edge: "w", dx: 40, dy: 0, expected: { left: 140, top: 100, width: 260, height: 300 } },
      { edge: "s", dx: 0, dy: 40, expected: { left: 100, top: 100, width: 300, height: 340 } },
      { edge: "n", dx: 0, dy: 40, expected: { left: 100, top: 140, width: 300, height: 260 } },
      { edge: "se", dx: 40, dy: 30, expected: { left: 100, top: 100, width: 340, height: 330 } },
      { edge: "sw", dx: 40, dy: 30, expected: { left: 140, top: 100, width: 260, height: 330 } },
      { edge: "ne", dx: 40, dy: 30, expected: { left: 100, top: 130, width: 340, height: 270 } },
      { edge: "nw", dx: 40, dy: 30, expected: { left: 140, top: 130, width: 260, height: 270 } },
    ])("the $edge handle moves only its own edges", ({ edge, dx, dy, expected }) => {
      drag(handle(edge), dx, dy);

      expect(applied()).toEqual(expected);
    });

    it("stops at the 240x240 minimum and keeps the opposite edge in place", () => {
      drag(handle("w"), 500, 0);
      expect(applied()).toMatchObject({ left: 160, width: 240 });

      drag(handle("n"), 0, 500);
      expect(applied()).toMatchObject({ top: 160, height: 240 });

      drag(handle("e"), -500, 0);
      expect(applied()).toMatchObject({ left: 160, width: 240 });

      drag(handle("s"), 0, -500);
      expect(applied()).toMatchObject({ top: 160, height: 240 });
    });

    it("cannot be enlarged past the viewport", () => {
      drag(handle("se"), 5000, 5000);
      expect(applied()).toEqual({ left: 100, top: 100, width: 924, height: 668 });

      drag(handle("nw"), -5000, -5000);
      expect(applied()).toEqual({ left: 0, top: 0, width: 1024, height: 768 });
    });

    it("saves once on release and not while moving", () => {
      const setItem = vi.spyOn(Storage.prototype, "setItem");
      pointer(handle("e"), "pointerdown", { x: 0, y: 0 });

      pointer(handle("e"), "pointermove", { x: 20, y: 0 });
      pointer(handle("e"), "pointermove", { x: 40, y: 0 });
      expect(setItem).not.toHaveBeenCalled();

      pointer(handle("e"), "pointerup", { x: 40, y: 0 });
      const saves = setItem.mock.calls.filter((call) => call[0] === LAYOUT_KEY);
      expect(saves).toHaveLength(1);
      expect(JSON.parse(saves[0][1])).toEqual({ left: 100, top: 100, width: 340, height: 300 });
    });

    it("cancels the press so the text is not selected and the conversation does not scroll", () => {
      const event = pointer(handle("se"), "pointerdown", { x: 0, y: 0 });

      expect(event.defaultPrevented).toBe(true);
    });

    it("captures the pointer on the handle", () => {
      pointer(handle("n"), "pointerdown", { x: 0, y: 0, id: 9 });

      expect(Element.prototype.setPointerCapture).toHaveBeenCalledWith(9);
    });
  });

  describe("window resize", () => {
    it("fits the popup to a smaller viewport without saving", () => {
      stubViewport(380, 300);
      const setItem = vi.spyOn(Storage.prototype, "setItem");

      window.dispatchEvent(new Event("resize"));

      expect(applied()).toEqual({ left: 80, top: 0, width: 300, height: 300 });
      expect(setItem).not.toHaveBeenCalled();
      expect(JSON.parse(localStorage.getItem(LAYOUT_KEY))).toEqual(START);
    });

    it("restores the saved layout when the window is large again", () => {
      stubViewport(380, 300);
      window.dispatchEvent(new Event("resize"));

      stubViewport(1024, 768);
      window.dispatchEvent(new Event("resize"));

      expect(applied()).toEqual(START);
    });

    it("does nothing while the chat is in the sidebar", () => {
      closeAndFinish(popup);
      stubViewport(380, 300);

      window.dispatchEvent(new Event("resize"));

      expect(sidebar.style.left).toBe("");
    });
  });

  describe("remembering the layout (SC-004)", () => {
    it("opens at the moved and resized layout after closing", () => {
      drag(header, 40, 40);
      drag(handle("se"), 20, 20);
      closeAndFinish(popup);

      popup.open();

      expect(applied()).toEqual({ left: 140, top: 140, width: 320, height: 320 });
    });

    it("opens at the saved layout in a new tab with the same localStorage", async () => {
      drag(header, 40, 40);
      drag(handle("se"), 20, 20);
      teardownPage();
      sidebar = buildPage();
      stubRect(sidebar, { left: 800, top: 100, width: 240, height: 600 });
      vi.stubGlobal("ai_helper", { userId: USER_ID });
      stubViewport(1024, 768);
      stubMatchMedia(false);
      sessionStorage.clear();
      popup = await load();
      popup.init();
      expect(sidebar.parentElement).toBe(document.getElementById("sidebar-wrapper"));

      popup.open();

      expect(applied()).toEqual({ left: 140, top: 140, width: 320, height: 320 });
    });
  });
});

describe("AiHelperChatPopup missing markup", () => {
  beforeEach(() => {
    setupPage();
    stubMatchMedia(false);
  });

  afterEach(teardownPage);

  it("throws when #aihelper-sidebar is not on the page", async () => {
    const popup = await load();
    popup.init();
    document.getElementById("aihelper-sidebar").remove();

    expect(() => popup.open()).toThrow(/#aihelper-sidebar not found/);
  });

  it("throws on init() when a control rendered by the ERB is missing", async () => {
    const popup = await load();
    document.getElementById("aihelper-popup-open").remove();

    expect(() => popup.init()).toThrow(/#aihelper-popup-open not found/);
  });

  it("throws on close() when #sidebar-wrapper is gone", async () => {
    const popup = await load();
    popup.init();
    popup.open();
    document.getElementById("sidebar-wrapper").remove();

    expect(() => popup.close()).toThrow(/#sidebar-wrapper not found/);
  });
});
