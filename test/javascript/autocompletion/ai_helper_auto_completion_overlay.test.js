import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";

/**
 * Helper: Create a minimal DOM environment for a single textarea instance.
 */
function createTextareaDOM() {
  const container = document.createElement("div");

  const textarea = document.createElement("textarea");
  textarea.id = "textarea-description";
  container.appendChild(textarea);

  const checkboxContainer = document.createElement("div");
  checkboxContainer.id = "ai-helper-description-checkbox-container";

  const checkbox = document.createElement("input");
  checkbox.type = "checkbox";
  checkbox.id = "ai-helper-autocompletion-description-toggle";
  checkboxContainer.appendChild(checkbox);
  container.appendChild(checkboxContainer);

  document.body.appendChild(container);

  return { container, textarea, checkbox };
}

/**
 * Helper: Build an initialized AiHelperAutoCompletion instance in enabled state.
 */
function createCompletion(textarea, options = {}) {
  const completion = new window.AiHelperAutoCompletion(textarea, {
    endpoint: "/projects/1/ai_helper/issue/1/suggest_completion",
    debounceDelay: 0,
    minLength: 1,
    ...options,
  });
  completion.init();
  completion.isEnabled = true;
  if (completion.checkbox) {
    completion.checkbox.checked = true;
  }
  return completion;
}

/**
 * Helper: Show a suggestion taller than the overlay so checkAndEnableScrolling
 * takes the scrollable branch (jsdom does no layout, so heights are stubbed).
 */
function makeOverflowing(dom, completion) {
  dom.textarea.style.height = "50px";
  dom.textarea.value = "hello";
  dom.textarea.setSelectionRange(5, 5);
  completion.displayInlineSuggestion("\n".repeat(20), 5);

  Object.defineProperty(completion.overlay, "scrollHeight", { value: 500, configurable: true });
  Object.defineProperty(completion.overlay, "clientHeight", { value: 50, configurable: true });
}

/**
 * Helper: Record child list changes of a node; read them with takeRecords().
 */
function observeChildList(node) {
  const observer = new MutationObserver(() => {});
  observer.observe(node, { childList: true });
  return observer;
}

describe("AiHelperAutoCompletion overlay", () => {
  let container;

  beforeEach(async () => {
    await loadScript("assets/javascripts/autocompletion/ai_helper_auto_completion");
    await loadScript("assets/javascripts/autocompletion/ai_helper_auto_completion_overlay");
  });

  afterEach(() => {
    if (container) {container.remove();}
    container = undefined;
  });

  describe("displayInlineSuggestion", () => {
    it("sets up overlay with before, suggestion, and after spans", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "hello world";
      dom.textarea.setSelectionRange(5, 5);

      completion.displayInlineSuggestion(" friend", 5);

      expect(completion.currentSuggestion).toEqual({
        text: " friend",
        cursorPosition: 5,
      });
      expect(completion.overlay.innerHTML).toContain("friend");
      expect(dom.textarea.style.color).toBe("transparent");
    });

    it("handles empty suggestion text", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "hello";
      completion.displayInlineSuggestion("", 5);

      expect(completion.currentSuggestion.text).toBe("");
    });
  });

  describe("getTextareaBackgroundColor", () => {
    it("returns textarea background when not transparent", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);
      dom.textarea.style.backgroundColor = "rgb(200, 200, 255)";

      expect(completion.getTextareaBackgroundColor()).toBe("rgb(200, 200, 255)");
    });

    it("returns parent background when textarea is transparent", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);
      dom.textarea.style.backgroundColor = "transparent";
      dom.container.style.backgroundColor = "rgb(240, 240, 240)";

      expect(completion.getTextareaBackgroundColor()).toBe("rgb(240, 240, 240)");
    });

    it("defaults to white when both are transparent", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);
      dom.textarea.style.backgroundColor = "transparent";
      dom.container.style.backgroundColor = "transparent";

      expect(completion.getTextareaBackgroundColor()).toBe("#ffffff");
    });

    it("static resolveBackgroundColor works with any element", () => {
      const el = document.createElement("div");
      el.style.backgroundColor = "rgb(100, 100, 100)";
      document.body.appendChild(el);

      expect(window.AiHelperAutoCompletion.resolveBackgroundColor(el)).toBe("rgb(100, 100, 100)");
      el.remove();
    });
  });

  describe("clearSuggestion", () => {
    it("calls forgetRequestSnapshot when currentSuggestion is set", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "hello world";
      dom.textarea.setSelectionRange(5, 5);
      completion.displayInlineSuggestion(" friend", 5);

      const spy = vi.spyOn(completion, "forgetRequestSnapshot");
      completion.clearSuggestion();

      expect(spy).toHaveBeenCalledWith("hello world", 5);
      expect(completion.currentSuggestion).toBeNull();
      expect(completion.overlay.innerHTML).toBe("");
    });

    it("resets overlay backgroundColor to transparent", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      completion.displayInlineSuggestion(" test", 0);
      completion.clearSuggestion();

      expect(completion.overlay.style.backgroundColor).toBe("transparent");
    });
  });

  describe("syncScroll", () => {
    it("copies textarea scroll position to overlay", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "hello world";
      dom.textarea.setSelectionRange(5, 5);
      completion.displayInlineSuggestion(" friend", 5);

      dom.textarea.scrollTop = 10;
      dom.textarea.scrollLeft = 5;
      completion.syncScroll();

      expect(completion.overlay.scrollTop).toBe(10);
      expect(completion.overlay.scrollLeft).toBe(5);
    });
  });

  describe("checkAndEnableScrolling", () => {
    it("enables scrollable mode and moves the overlay after the textarea", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);
      makeOverflowing(dom, completion);

      completion.checkAndEnableScrolling();

      expect(completion.overlay.style.overflowY).toBe("auto");
      expect(completion.overlay.classList.contains("ai-helper-scrollable-overlay")).toBe(true);
      expect(dom.textarea.nextSibling).toBe(completion.overlay);
      expect(dom.container.children[0]).toBe(dom.textarea);
    });

    it("syncs the overlay scroll position right after moving it", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);
      makeOverflowing(dom, completion);

      dom.textarea.scrollTop = 12;
      dom.textarea.scrollLeft = 3;
      completion.checkAndEnableScrolling();

      // jsdom does not reset scrollTop on a DOM move, so this only proves a
      // sync runs after the move, not that the browser's reset is undone
      expect(completion.overlay.scrollTop).toBe(12);
      expect(completion.overlay.scrollLeft).toBe(3);
    });

    it("does not move the overlay again when already in scrollable mode", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);
      makeOverflowing(dom, completion);
      completion.checkAndEnableScrolling();

      const observer = observeChildList(dom.container);
      completion.checkAndEnableScrolling();

      expect(observer.takeRecords()).toHaveLength(0);
      observer.disconnect();
    });

    it("moves the overlay back before the textarea when content fits again", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);
      makeOverflowing(dom, completion);
      completion.checkAndEnableScrolling();

      Object.defineProperty(completion.overlay, "scrollHeight", { value: 30, configurable: true });
      completion.checkAndEnableScrolling();

      expect(dom.textarea.previousSibling).toBe(completion.overlay);
      expect(completion.overlay.style.pointerEvents).toBe("none");
      expect(completion.overlay.classList.contains("ai-helper-scrollable-overlay")).toBe(false);
    });

    it("never sets an inline z-index in any state", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);
      makeOverflowing(dom, completion);

      completion.checkAndEnableScrolling();
      expect(completion.overlay.style.zIndex).toBe("");

      Object.defineProperty(completion.overlay, "scrollHeight", { value: 30, configurable: true });
      completion.checkAndEnableScrolling();
      expect(completion.overlay.style.zIndex).toBe("");
    });

    it("keeps a sibling inserted right after the textarea (typo overlay) above the completion overlay", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      // Same insertion the typo checker uses for its overlay
      const typoOverlay = document.createElement("div");
      dom.container.insertBefore(typoOverlay, dom.textarea.nextSibling);

      makeOverflowing(dom, completion);
      completion.checkAndEnableScrolling();

      const children = Array.from(dom.container.children);
      expect(children.indexOf(dom.textarea)).toBe(0);
      expect(children.indexOf(completion.overlay)).toBe(1);
      expect(children.indexOf(typoOverlay)).toBe(2);
    });

    it("does not throw when the textarea has been detached", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);
      makeOverflowing(dom, completion);
      dom.textarea.remove();

      expect(() => completion.checkAndEnableScrolling()).not.toThrow();
      Object.defineProperty(completion.overlay, "scrollHeight", { value: 30, configurable: true });
      expect(() => completion.checkAndEnableScrolling()).not.toThrow();
    });

    it("does not re-insert the overlay after destroy()", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);
      makeOverflowing(dom, completion);

      const overlay = completion.overlay;
      completion.destroy();
      // Simulates the setTimeout(0) from displayInlineSuggestion firing late
      completion.checkAndEnableScrolling();
      expect(overlay.isConnected).toBe(false);

      // Same for the non-scrollable branch
      Object.defineProperty(overlay, "scrollHeight", { value: 30, configurable: true });
      completion.checkAndEnableScrolling();
      expect(overlay.isConnected).toBe(false);
    });
  });

  describe("addScrollableEventListeners", () => {
    it("forwards non-suggestion clicks to textarea", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "hello";
      dom.textarea.setSelectionRange(5, 5);
      completion.displayInlineSuggestion(" world", 5);

      completion.addScrollableEventListeners();

      const focusSpy = vi.spyOn(dom.textarea, "focus");
      completion.overlay.dispatchEvent(new MouseEvent("click", { bubbles: true }));

      expect(focusSpy).toHaveBeenCalled();
      completion.removeScrollableEventListeners();
    });

    it("forwards non-scroll keydown events to textarea", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "hello";
      dom.textarea.setSelectionRange(5, 5);
      completion.displayInlineSuggestion(" world", 5);

      completion.addScrollableEventListeners();

      const focusSpy = vi.spyOn(dom.textarea, "focus");
      completion.overlay.dispatchEvent(new KeyboardEvent("keydown", { key: "a", bubbles: true }));

      expect(focusSpy).toHaveBeenCalled();
      completion.removeScrollableEventListeners();
    });
  });

  describe("removeScrollableEventListeners", () => {
    it("removes listeners and nulls handlers", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "hello";
      dom.textarea.setSelectionRange(5, 5);
      completion.displayInlineSuggestion(" world", 5);

      completion.addScrollableEventListeners();
      completion.removeScrollableEventListeners();

      expect(completion.scrollableClickHandler).toBeNull();
      expect(completion.scrollableKeydownHandler).toBeNull();
    });
  });

  describe("resetScrolling", () => {
    it("resets scrolling styles and moves the overlay back before the textarea", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "hello";
      dom.textarea.setSelectionRange(5, 5);
      completion.displayInlineSuggestion(" world", 5);

      completion.overlay.style.overflowY = "auto";
      completion.overlay.classList.add("ai-helper-scrollable-overlay");
      dom.textarea.parentNode.insertBefore(completion.overlay, dom.textarea.nextSibling);

      completion.resetScrolling();

      expect(completion.overlay.style.overflowY).toBe("hidden");
      expect(completion.overlay.classList.contains("ai-helper-scrollable-overlay")).toBe(false);
      expect(dom.textarea.previousSibling).toBe(completion.overlay);
      expect(completion.overlay.style.zIndex).toBe("");
    });

    it("syncs the overlay scroll position when moving it back", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "hello";
      dom.textarea.setSelectionRange(5, 5);
      completion.displayInlineSuggestion(" world", 5);

      dom.textarea.parentNode.insertBefore(completion.overlay, dom.textarea.nextSibling);
      dom.textarea.scrollTop = 7;
      completion.resetScrolling();

      expect(completion.overlay.scrollTop).toBe(7);
    });

    it("does not move the overlay when it is already in place", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "hello";
      dom.textarea.setSelectionRange(5, 5);
      completion.displayInlineSuggestion(" world", 5);

      const observer = observeChildList(dom.container);
      completion.resetScrolling();

      expect(observer.takeRecords()).toHaveLength(0);
      expect(dom.textarea.previousSibling).toBe(completion.overlay);
      observer.disconnect();
    });
  });
});
