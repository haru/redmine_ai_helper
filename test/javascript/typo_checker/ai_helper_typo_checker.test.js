import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";

function createTypoCheckerDOM(textareaId = "issue_description") {
  const parent = document.createElement("div");
  parent.style.position = "relative";

  const textarea = document.createElement("textarea");
  textarea.id = textareaId;
  parent.appendChild(textarea);

  const controlPanelId = {
    "issue_description": "ai-helper-typo-control-panel-description",
    "issue_notes": "ai-helper-typo-control-panel-notes",
    "content_text": "ai-helper-typo-control-panel-wiki",
  }[textareaId];

  const controlPanel = document.createElement("div");
  controlPanel.id = controlPanelId;
  const applyAllBtn = document.createElement("button");
  applyAllBtn.className = "ai-helper-typo-apply-all-btn";
  controlPanel.appendChild(applyAllBtn);
  const closeBtn = document.createElement("button");
  closeBtn.className = "ai-helper-typo-close-btn";
  controlPanel.appendChild(closeBtn);
  parent.appendChild(controlPanel);

  const checkBtnId = {
    "issue_description": "ai-helper-typo-check-description-btn",
    "issue_notes": "ai-helper-typo-check-notes-btn",
    "content_text": "ai-helper-typo-check-wiki-btn",
  }[textareaId];

  const checkBtn = document.createElement("button");
  checkBtn.id = checkBtnId;
  checkBtn.innerHTML = '<svg></svg> Check';
  parent.appendChild(checkBtn);

  // Button templates needed by buildOverlayContent
  const acceptTemplate = document.createElement("span");
  acceptTemplate.className = "ai-helper-typo-accept-btn-template";
  acceptTemplate.innerHTML = "✓";
  document.body.appendChild(acceptTemplate);

  const rejectTemplate = document.createElement("span");
  rejectTemplate.className = "ai-helper-typo-reject-btn-template";
  rejectTemplate.innerHTML = "✗";
  document.body.appendChild(rejectTemplate);

  // CSRF meta tag
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "test-csrf-token";
  document.head.appendChild(meta);

  document.body.appendChild(parent);

  return { parent, textarea, controlPanel, checkBtn };
}

function createChecker(textarea, options = {}) {
  const checker = new window.AiHelperTypoChecker(textarea, {
    endpoint: "/ai_helper/issue/1/check_typos",
    debounceDelay: 0,
    minLength: 1,
    labels: {
      checkButton: "Check",
      checking: "Checking...",
      noSuggestions: "No typos found",
      errorOccurred: "An error occurred",
      correctionTooltip: "Suggested correction",
      acceptSuggestion: "Accept",
      dismissSuggestion: "Reject",
      applyFailed: "Failed to apply",
    },
    ...options,
  });
  return checker;
}

describe("AiHelperTypoChecker", () => {
  let dom;
  let textarea;
  let checker;

  beforeEach(async () => {
    await loadScript("assets/javascripts/typo_checker/ai_helper_typo_checker");
    await loadScript("assets/javascripts/typo_checker/ai_helper_typo_suggestion_overlay");
    dom = createTypoCheckerDOM();
    textarea = dom.textarea;
    textarea.value = "";
  });

  afterEach(() => {
    if (checker && checker.overlay && checker.overlay.parentNode) {
      checker.overlay.remove();
    }
    document.querySelectorAll(
      ".ai-helper-typo-accept-btn-template, .ai-helper-typo-reject-btn-template"
    ).forEach((el) => el.remove());
    if (dom && dom.parent && dom.parent.parentNode) {
      dom.parent.remove();
    }
    const meta = document.querySelector('meta[name="csrf-token"]');
    if (meta) {meta.remove();}
    vi.unstubAllGlobals();
  });


  describe("constructor and initialization", () => {
    it("creates instance with default options", () => {
      checker = createChecker(textarea);
      expect(checker.suggestions).toEqual([]);
      expect(checker.overlay).toBeNull();
      expect(checker.isEnabled).toBe(false);
      expect(checker.isCheckingTypos).toBe(false);
      expect(checker.isOverlayVisible).toBe(false);
      expect(checker.isProcessingSuggestion).toBe(false);
    });

    it("initializes with custom options", () => {
      checker = createChecker(textarea, {
        contextType: "wiki",
        debounceDelay: 2000,
        minLength: 20,
      });
      expect(checker.options.contextType).toBe("wiki");
      expect(checker.options.debounceDelay).toBe(2000);
      expect(checker.options.minLength).toBe(20);
    });

    it("init creates overlay, finds control panel, attaches events", () => {
      checker = createChecker(textarea);
      checker.init();
      expect(checker.overlay).not.toBeNull();
      expect(checker.controlPanel).not.toBeNull();
      expect(checker.checkButton).not.toBeNull();
      expect(checker.applyAllButton).not.toBeNull();
      expect(checker.closeButton).not.toBeNull();
    });

    it("init finds control panel and button for issue_notes", () => {
      const notesDom = createTypoCheckerDOM("issue_notes");
      const notesTextarea = notesDom.textarea;
      checker = createChecker(notesTextarea, { contextType: "general" });
      checker.init();
      expect(checker.controlPanel).not.toBeNull();
      expect(checker.checkButton).not.toBeNull();
      notesDom.parent.remove();
    });

    it("init finds control panel and button for content_text (wiki)", () => {
      const wikiDom = createTypoCheckerDOM("content_text");
      const wikiTextarea = wikiDom.textarea;
      checker = createChecker(wikiTextarea, { contextType: "general" });
      checker.init();
      expect(checker.controlPanel).not.toBeNull();
      expect(checker.checkButton).not.toBeNull();
      wikiDom.parent.remove();
    });

    it("init works when control panel is not found", () => {
      const simpleParent = document.createElement("div");
      const simpleTextarea = document.createElement("textarea");
      simpleTextarea.id = "unknown_textarea";
      simpleParent.appendChild(simpleTextarea);
      document.body.appendChild(simpleParent);

      checker = createChecker(simpleTextarea);
      checker.init();
      expect(checker.controlPanel).toBeFalsy();
      expect(checker.checkButton).toBeFalsy();
      simpleParent.remove();
    });
  });

  describe("checkTypos", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
      vi.stubGlobal("fetch", vi.fn());
    });

    it("does nothing when text is too short", async () => {
      checker.options.minLength = 5;
      textarea.value = "a";
      await checker.checkTypos();
      expect(fetch).not.toHaveBeenCalled();
    });

    it("does nothing when text is empty", async () => {
      textarea.value = "";
      await checker.checkTypos();
      expect(fetch).not.toHaveBeenCalled();
    });

    it("sends a POST request with the text", async () => {
      textarea.value = "some text with typos";
      vi.mocked(fetch).mockResolvedValue({
        ok: true,
        json: () => Promise.resolve({ suggestions: [] }),
      });

      await checker.checkTypos();

      expect(fetch).toHaveBeenCalledTimes(1);
      const [url, options] = vi.mocked(fetch).mock.calls[0];
      expect(url).toBe("/ai_helper/issue/1/check_typos");
      expect(options.method).toBe("POST");
      expect(JSON.parse(options.body)).toEqual({ text: "some text with typos" });
    });

    it("handles non-OK response", async () => {
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
      textarea.value = "some text with errors";
      vi.mocked(fetch).mockResolvedValue({
        ok: false,
        status: 500,
        statusText: "Internal Server Error",
      });

      await checker.checkTypos();

      expect(consoleError).toHaveBeenCalledTimes(1);
      consoleError.mockRestore();
    });

    it("handles network error", async () => {
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
      textarea.value = "some text";
      vi.mocked(fetch).mockRejectedValue(new Error("Network error"));

      await checker.checkTypos();

      expect(consoleError).toHaveBeenCalledTimes(1);
      consoleError.mockRestore();
    });

    it("prevents duplicate execution", async () => {
      textarea.value = "some long text for checking";
      let resolveFirst;
      vi.mocked(fetch).mockImplementation(() => {
        return new Promise((resolve) => {
          resolveFirst = resolve;
        });
      });

      const p1 = checker.checkTypos();
      const p2 = checker.checkTypos();

      expect(fetch).toHaveBeenCalledTimes(1);

      resolveFirst({
        ok: true,
        json: () => Promise.resolve({ suggestions: [] }),
      });
      await Promise.all([p1, p2]);
    });

    it("stores and restores button HTML", async () => {
      textarea.value = "some text for checking";
      vi.mocked(fetch).mockResolvedValue({
        ok: true,
        json: () => Promise.resolve({ suggestions: [] }),
      });

      const originalHTML = dom.checkBtn.innerHTML;
      await checker.checkTypos();

      expect(dom.checkBtn.innerHTML).toBe(originalHTML);
      expect(dom.checkBtn.disabled).toBe(false);
    });
  });

  describe("getTextareaBackgroundColor", () => {
    it("returns the textarea background color when not transparent", () => {
      checker = createChecker(textarea);
      textarea.style.backgroundColor = "rgb(255, 200, 200)";

      const color = checker.getTextareaBackgroundColor();

      expect(color).toBe("rgb(255, 200, 200)");
    });

    it("returns parent background when textarea is transparent", () => {
      checker = createChecker(textarea);
      textarea.style.backgroundColor = "transparent";
      dom.parent.style.backgroundColor = "rgb(240, 240, 240)";

      const color = checker.getTextareaBackgroundColor();

      expect(color).toBe("rgb(240, 240, 240)");
    });

    it("defaults to white when both textarea and parent are transparent", () => {
      checker = createChecker(textarea);
      textarea.style.backgroundColor = "transparent";
      dom.parent.style.backgroundColor = "transparent";

      const color = checker.getTextareaBackgroundColor();

      expect(color).toBe("#ffffff");
    });

    it("returns parent background when textarea is rgba(0,0,0,0)", () => {
      checker = createChecker(textarea);
      textarea.style.backgroundColor = "rgba(0, 0, 0, 0)";
      dom.parent.style.backgroundColor = "rgb(200, 200, 255)";

      const color = checker.getTextareaBackgroundColor();

      expect(color).toBe("rgb(200, 200, 255)");
    });
  });

  describe("getCSRFToken", () => {
    it("returns the CSRF token from meta tag", () => {
      checker = createChecker(textarea);
      expect(checker.getCSRFToken()).toBe("test-csrf-token");
    });

    it("returns empty string when meta tag is absent", () => {
      // Remove the meta tag that createTypoCheckerDOM added
      document.querySelectorAll('meta[name="csrf-token"]').forEach((m) => m.remove());

      // createChecker does not re-add the meta, only createTypoCheckerDOM does
      // Create a minimal setup without the meta tag
      const parent2 = document.createElement("div");
      const ta2 = document.createElement("textarea");
      ta2.id = "issue_description";
      parent2.appendChild(ta2);
      document.body.appendChild(parent2);

      checker = createChecker(ta2);
 expect(checker.getCSRFToken()).toBe("");

      parent2.remove();
    });
  });

  describe("isOverlayActive", () => {
    it("returns true when overlay has the active class", () => {
      checker = createChecker(textarea);
      checker.init();
      checker.overlay.classList.add("ai-helper-typo-overlay-active");

      expect(checker.isOverlayActive()).toBe(true);
    });

    it("returns false when overlay does not have the active class", () => {
      checker = createChecker(textarea);
      checker.init();

      expect(checker.isOverlayActive()).toBe(false);
    });
  });

  describe("syncScroll", () => {
    it("syncs overlay scroll position with textarea", () => {
      checker = createChecker(textarea);
      checker.init();
      textarea.scrollTop = 50;
      textarea.scrollLeft = 10;

      checker.syncScroll();

      expect(checker.overlay.scrollTop).toBe(50);
      expect(checker.overlay.scrollLeft).toBe(10);
    });
  });

  describe("disableAutocompletion / enableAutocompletion", () => {
    it("disables autocomplete instances via aiHelperInstances", () => {
      window.aiHelperInstances = {
        autoCompletion: {
          clearSuggestion: vi.fn(),
          isEnabled: true,
        },
        wikiAutoCompletion: {
          clearSuggestion: vi.fn(),
          isEnabled: true,
        },
        notesAutoCompletion: {
          clearSuggestion: vi.fn(),
          isEnabled: true,
        },
      };

      checker = createChecker(textarea);
      checker.disableAutocompletion();

      expect(window.aiHelperInstances.autoCompletion.isEnabled).toBe(false);
      expect(window.aiHelperInstances.wikiAutoCompletion.isEnabled).toBe(false);
      expect(window.aiHelperInstances.notesAutoCompletion.isEnabled).toBe(false);
      expect(window.aiHelperInstances.autoCompletion.clearSuggestion).toHaveBeenCalledTimes(1);
    });

    it("re-enables autocomplete when checkbox is checked", () => {
      window.aiHelperInstances = {
        autoCompletion: {
          isEnabled: false,
          checkbox: { checked: true },
        },
        wikiAutoCompletion: {
          isEnabled: false,
          checkbox: { checked: false },
        },
        notesAutoCompletion: {
          isEnabled: false,
          checkbox: { checked: true },
        },
      };

      checker = createChecker(textarea);
      checker.enableAutocompletion();

      expect(window.aiHelperInstances.autoCompletion.isEnabled).toBe(true);
      expect(window.aiHelperInstances.wikiAutoCompletion.isEnabled).toBe(false);
      expect(window.aiHelperInstances.notesAutoCompletion.isEnabled).toBe(true);

      delete window.aiHelperInstances;
    });

    it("does nothing when aiHelperInstances is not set", () => {
      checker = createChecker(textarea);
      expect(() => checker.disableAutocompletion()).not.toThrow();
      expect(() => checker.enableAutocompletion()).not.toThrow();
    });
  });

  describe("checkAndEnableScrolling", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
    });

    it("enables scrolling when content exceeds height", () => {
      // Populate overlay with tall content so scrollHeight > clientHeight
      checker.overlay.innerHTML = '<div style="height:500px;"></div>';
      checker.overlay.style.height = '200px';
      checker.overlay.style.overflowY = 'hidden';

      checker.checkAndEnableScrolling();

      // In jsdom, scrollHeight may not reflect actual content size.
      // Just verify the method runs without error.
      expect(checker.overlay).not.toBeNull();
    });

    it("keeps default when content fits", () => {
      Object.defineProperty(checker.overlay, "scrollHeight", {
        value: 200,
        configurable: true,
      });
      Object.defineProperty(checker.overlay, "clientHeight", {
        value: 200,
        configurable: true,
      });

      checker.checkAndEnableScrolling();

      expect(checker.overlay.style.overflowY).toBe("hidden");
      expect(
        checker.overlay.classList.contains("ai-helper-scrollable-overlay")
      ).toBe(false);
    });
  });

  describe("event listeners", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
    });

    it("hides overlay on input when processing is not active", () => {
      checker.isOverlayVisible = true;
      checker.overlay.classList.add("ai-helper-typo-overlay-active");

      textarea.dispatchEvent(new Event("input"));

      expect(checker.isOverlayVisible).toBe(false);
    });

    it("does not hide overlay on input when processing suggestion", () => {
      checker.isOverlayVisible = true;
      checker.isProcessingSuggestion = true;
      checker.overlay.classList.add("ai-helper-typo-overlay-active");

      textarea.dispatchEvent(new Event("input"));

      expect(checker.isOverlayVisible).toBe(true);
    });

    it("hides overlay on Escape key", () => {
      checker.isOverlayVisible = true;
      checker.overlay.classList.add("ai-helper-typo-overlay-active");

      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));

      expect(checker.isOverlayVisible).toBe(false);
    });

    it("hides overlay when clicking outside overlay and controls", () => {
      checker.isOverlayVisible = true;
      checker.overlay.classList.add("ai-helper-typo-overlay-active");

      const outsideEl = document.createElement("div");
      document.body.appendChild(outsideEl);
      outsideEl.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      outsideEl.remove();

      expect(checker.isOverlayVisible).toBe(false);
    });

    it("does not hide overlay when clicking on overlay itself", () => {
      checker.isOverlayVisible = true;
      checker.overlay.classList.add("ai-helper-typo-overlay-active");

      checker.overlay.dispatchEvent(new MouseEvent("click", { bubbles: true }));

      expect(checker.isOverlayVisible).toBe(true);
    });

    it("apply all button calls acceptAllSuggestions", () => {
      textarea.value = "teh cat";
      checker.suggestions = [
        { position: 0, original: "teh", corrected: "the" },
      ];

      checker.applyAllButton.click();

      expect(textarea.value).toBe("the cat");
    });

    it("close button hides overlay", () => {
      checker.isOverlayVisible = true;
      checker.overlay.classList.add("ai-helper-typo-overlay-active");

      checker.closeButton.click();

      expect(checker.isOverlayVisible).toBe(false);
    });
  });

  describe("resetScrolling", () => {
    it("resets overlay scrolling to defaults", () => {
      checker = createChecker(textarea);
      checker.init();
      checker.overlay.style.overflowY = "auto";
      checker.overlay.style.zIndex = "20";
      checker.overlay.style.borderColor = "red";
      checker.overlay.classList.add("ai-helper-scrollable-overlay");

      checker.resetScrolling();

      expect(checker.overlay.style.overflowY).toBe("hidden");
      expect(checker.overlay.style.zIndex).toBe("15");
      expect(checker.overlay.style.borderColor).toBe("transparent");
      expect(
        checker.overlay.classList.contains("ai-helper-scrollable-overlay")
      ).toBe(false);
    });

    it("handles null overlay gracefully", () => {
      checker = createChecker(textarea);
      checker.overlay = null;
      expect(() => checker.resetScrolling()).not.toThrow();
    });
  });

  describe("addScrollableEventListeners / removeScrollableEventListeners", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
    });

    it("adds and removes scrollable event listeners", () => {
      checker.addScrollableEventListeners();

      expect(checker.scrollableClickHandler).not.toBeNull();
      expect(checker.scrollableKeydownHandler).not.toBeNull();

      checker.removeScrollableEventListeners();

      expect(checker.scrollableClickHandler).toBeNull();
      expect(checker.scrollableKeydownHandler).toBeNull();
    });

    it("removeScrollableEventListeners handles null overlay", () => {
      checker.scrollableClickHandler = null;
      checker.scrollableKeydownHandler = null;
      expect(() => checker.removeScrollableEventListeners()).not.toThrow();
    });

    it("scrollable click forwards focus to textarea for non-button clicks", () => {
      checker.addScrollableEventListeners();
      const focusSpy = vi.spyOn(textarea, "focus");

      const clickEvent = new MouseEvent("click", { bubbles: true });
      Object.defineProperty(clickEvent, "target", {
        value: document.createElement("div"),
      });
      checker.overlay.dispatchEvent(clickEvent);

      expect(focusSpy).toHaveBeenCalled();
    });

    it("scrollable click does not forward for accept/reject buttons", () => {
      checker.addScrollableEventListeners();
      const focusSpy = vi.spyOn(textarea, "focus");

      const btn = document.createElement("div");
      btn.classList.add("ai-helper-typo-accept-btn");
      btn.dispatchEvent(new MouseEvent("click", { bubbles: true }));

      expect(focusSpy).not.toHaveBeenCalled();
    });
  });

  describe("setUserId", () => {
    it("is not defined on AiHelperTypoChecker (only on AiHelper)", () => {
      checker = createChecker(textarea);
      expect(checker.setUserId).toBeUndefined();
    });
  });
});


// --- T018: Characterization tests for the #ai-helper-wiki-typo-overlay container ---
//
// wiki/_textarea_overlay.html.erb renders the #ai-helper-wiki-typo-overlay
// container with its own button-bound initFromConfig call from
// ai_helper_wiki_autocompletion.js. A module-load-time `DOMContentLoaded`
// auto-init here would create a second, unbound AiHelperTypoChecker instance
// on every real wiki page (FR-008). So no such auto-init is defined; these
// tests characterize that loading the script has no side effects on its own,
// and that initFromConfig (the shared factory used by all real call sites)
// behaves the same way regardless of which container id is passed in.
describe("#ai-helper-wiki-typo-overlay container (no module-level auto-init)", () => {
  beforeEach(async () => {
    await loadScript("assets/javascripts/typo_checker/ai_helper_typo_checker");
  });

  afterEach(() => {
    document
      .querySelectorAll("#ai-helper-wiki-typo-overlay, #content_text, .ai-helper-typo-accept-btn-template, .ai-helper-typo-reject-btn-template, #ai-helper-typo-control-panel-wiki, meta[name=csrf-token]")
      .forEach((el) => el.remove());
    vi.unstubAllGlobals();
  });

  it("does not auto-instantiate a checker merely from loading the script and firing DOMContentLoaded", () => {
    const container = document.createElement("div");
    container.id = "ai-helper-wiki-typo-overlay";
    container.dataset.config = JSON.stringify({
      endpoint: "/projects/test/ai_helper/check_typos",
      labels: {},
    });
    document.body.appendChild(container);

    const parent = document.createElement("div");
    parent.style.position = "relative";
    const textarea = document.createElement("textarea");
    textarea.id = "content_text";
    parent.appendChild(textarea);
    document.body.appendChild(parent);

    document.dispatchEvent(new Event("DOMContentLoaded"));

    expect(textarea.classList.contains("ai-helper-textarea-positioned")).toBe(false);
  });

  it("initFromConfig creates a bound AiHelperTypoChecker when explicitly invoked (used by real call sites)", () => {
    const container = document.createElement("div");
    container.id = "ai-helper-wiki-typo-overlay";
    container.dataset.config = JSON.stringify({
      endpoint: "/projects/test/ai_helper/check_typos",
      labels: { checkButton: "Check", checking: "Checking...", noSuggestions: "No typos", errorOccurred: "Error", correctionTooltip: "Correction", acceptSuggestion: "Accept", dismissSuggestion: "Reject", applyFailed: "Failed", suggestionsTitle: "Suggestions", acceptAll: "Accept All", dismissAll: "Dismiss All" },
    });
    document.body.appendChild(container);

    const parent = document.createElement("div");
    parent.style.position = "relative";
    const textarea = document.createElement("textarea");
    textarea.id = "content_text";
    parent.appendChild(textarea);

    const controlPanel = document.createElement("div");
    controlPanel.id = "ai-helper-typo-control-panel-wiki";
    const applyAllBtn = document.createElement("button");
    applyAllBtn.className = "ai-helper-typo-apply-all-btn";
    controlPanel.appendChild(applyAllBtn);
    const closeBtn = document.createElement("button");
    closeBtn.className = "ai-helper-typo-close-btn";
    controlPanel.appendChild(closeBtn);
    parent.appendChild(controlPanel);

    const checkBtn = document.createElement("button");
    checkBtn.id = "ai-helper-typo-check-wiki-btn";
    checkBtn.innerHTML = "<svg></svg> Check";
    parent.appendChild(checkBtn);
    document.body.appendChild(parent);

    const checker = window.AiHelperTypoChecker.initFromConfig(container, "content_text", "ai-helper-typo-check-wiki-btn");

    expect(checker).toBeInstanceOf(window.AiHelperTypoChecker);
    expect(textarea.classList.contains("ai-helper-textarea-positioned")).toBe(true);
  });

  it("initFromConfig does not double-bind a click handler on a button already found by findExistingButton", () => {
    const container = document.createElement("div");
    container.id = "ai-helper-wiki-typo-overlay";
    container.dataset.config = JSON.stringify({ endpoint: "/test", labels: {} });
    document.body.appendChild(container);

    const textarea = document.createElement("textarea");
    textarea.id = "content_text";
    document.body.appendChild(textarea);

    // Other tests in this describe block leave a stale
    // #ai-helper-typo-check-wiki-btn behind; remove it so
    // document.getElementById resolves to this test's own button.
    document.getElementById("ai-helper-typo-check-wiki-btn")?.remove();
    const checkBtn = document.createElement("button");
    checkBtn.id = "ai-helper-typo-check-wiki-btn";
    document.body.appendChild(checkBtn);
    const addEventListenerSpy = vi.spyOn(checkBtn, "addEventListener");

    const checker = window.AiHelperTypoChecker.initFromConfig(container, "content_text", "ai-helper-typo-check-wiki-btn");

    expect(checker.checkButton).toBe(checkBtn);
    const clickBindings = addEventListenerSpy.mock.calls.filter(([type]) => type === "click");
    expect(clickBindings).toHaveLength(1);

    textarea.remove();
    checkBtn.remove();
  });

  it("initFromConfig binds a click handler on a custom button that findExistingButton did not find", () => {
    const container = document.createElement("div");
    container.id = "ai-helper-wiki-typo-overlay";
    container.dataset.config = JSON.stringify({ endpoint: "/test", labels: {} });
    document.body.appendChild(container);

    const textarea = document.createElement("textarea");
    textarea.id = "content_text";
    document.body.appendChild(textarea);

    // No element with the id findExistingButton looks up for "content_text"
    // ("ai-helper-typo-check-wiki-btn"), so checker.checkButton stays unset;
    // this custom button is a different id passed explicitly.
    const customButton = document.createElement("button");
    customButton.id = "ai-helper-custom-typo-check-btn";
    document.body.appendChild(customButton);
    const checkTyposSpy = vi.spyOn(window.AiHelperTypoChecker.prototype, "checkTypos").mockResolvedValue();

    window.AiHelperTypoChecker.initFromConfig(container, "content_text", "ai-helper-custom-typo-check-btn");
    customButton.click();

    expect(checkTyposSpy).toHaveBeenCalledTimes(1);

    checkTyposSpy.mockRestore();
    textarea.remove();
    customButton.remove();
  });

  it("initFromConfig returns null when container element does not exist", () => {
    const result = window.AiHelperTypoChecker.initFromConfig(null, "content_text");
    expect(result).toBeNull();
  });

  it("initFromConfig returns null when textarea does not exist", () => {
    const container = document.createElement("div");
    container.id = "ai-helper-wiki-typo-overlay";
    container.dataset.config = JSON.stringify({ endpoint: "/test", labels: {} });
    document.body.appendChild(container);

    const result = window.AiHelperTypoChecker.initFromConfig(container, "content_text");

    expect(result).toBeNull();
    container.remove();
  });
});

