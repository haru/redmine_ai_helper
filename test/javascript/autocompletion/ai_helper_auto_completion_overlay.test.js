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

      dom.textarea.style.height = "50px";
      dom.textarea.value = "hello";
      dom.textarea.setSelectionRange(5, 5);
      completion.displayInlineSuggestion("\n".repeat(20), 5);

      Object.defineProperty(completion.overlay, "scrollHeight", { value: 500, configurable: true });
      Object.defineProperty(completion.overlay, "clientHeight", { value: 50, configurable: true });

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

      dom.textarea.style.height = "50px";
      dom.textarea.value = "hello";
      dom.textarea.setSelectionRange(5, 5);
      completion.displayInlineSuggestion("\n".repeat(20), 5);

      Object.defineProperty(completion.overlay, "scrollHeight", { value: 500, configurable: true });
      Object.defineProperty(completion.overlay, "clientHeight", { value: 50, configurable: true });

      dom.textarea.scrollTop = 12;
      dom.textarea.scrollLeft = 3;
      completion.checkAndEnableScrolling();

      expect(completion.overlay.scrollTop).toBe(12);
      expect(completion.overlay.scrollLeft).toBe(3);
    });

    it("never sets an inline z-index in any state", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.style.height = "50px";
      dom.textarea.value = "hello";
      dom.textarea.setSelectionRange(5, 5);
      completion.displayInlineSuggestion("\n".repeat(20), 5);

      Object.defineProperty(completion.overlay, "scrollHeight", { value: 500, configurable: true });
      Object.defineProperty(completion.overlay, "clientHeight", { value: 50, configurable: true });

      completion.checkAndEnableScrolling();
      expect(completion.overlay.style.zIndex).toBe("");

      Object.defineProperty(completion.overlay, "scrollHeight", { value: 30, configurable: true });
      completion.checkAndEnableScrolling();
      expect(completion.overlay.style.zIndex).toBe("");
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

    it("does not call insertBefore when the overlay is already in place", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "hello";
      dom.textarea.setSelectionRange(5, 5);
      completion.displayInlineSuggestion(" world", 5);

      const insertBeforeSpy = vi.spyOn(dom.container, "insertBefore");
      completion.resetScrolling();

      expect(insertBeforeSpy).not.toHaveBeenCalled();
      expect(dom.textarea.previousSibling).toBe(completion.overlay);
    });
  });
});
