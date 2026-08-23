import { afterEach, beforeEach, describe, expect, it } from "vitest";
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
});
