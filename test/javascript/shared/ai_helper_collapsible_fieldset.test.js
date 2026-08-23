import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";
import { loadScriptAndFireDOMContentLoaded } from "../support/dom_content_loaded.js";

// T039: characterization tests for issues/_form.html.erb extraction.

describe("ai_helper_collapsible_fieldset", () => {
  let container;
  let aiHelperMock;

  function addFieldset(config = {}) {
    container = document.createElement("fieldset");
    container.id = "ai-helper-reply-fields";
    container.className = "collapsible collapsed";
    const legend = document.createElement("legend");
    container.appendChild(legend);
    container.dataset.config = JSON.stringify({
      userId: 7,
      generateReplyUrl: "/issues/1/ai_helper/generate_reply",
      errorMessage: "Error occurred",
      applyLabel: "Apply",
      copyIconHtml: "<span>copy</span>",
      ...config,
    });
    document.body.appendChild(container);
    return container;
  }

  beforeEach(() => {
    aiHelperMock = { generateReplyStream: vi.fn() };
    vi.stubGlobal("ai_helper", aiHelperMock);
    vi.stubGlobal("toggleFieldset", vi.fn((legend) => {
      legend.closest("fieldset").classList.toggle("collapsed");
    }));
  });

  afterEach(() => {
    container?.remove();
    container = undefined;
    vi.unstubAllGlobals();
    localStorage.clear();
    delete window.aiHelperSaveReplyState;
    delete window.ai_helper_generate_reply;
  });

  describe("AiHelperCollapsibleFieldset.setExpanded (window-exposed, T045 shared helper)", () => {
    afterEach(() => {
      delete window.AiHelperCollapsibleFieldset;
    });

    it("expands a collapsed fieldset by toggling it", async () => {
      addFieldset();
      container.classList.add("collapsed");
      await loadScript("assets/javascripts/shared/ai_helper_collapsible_fieldset");

      window.AiHelperCollapsibleFieldset.setExpanded("ai-helper-reply-fields", true);

      expect(container.classList.contains("collapsed")).toBe(false);
    });

    it("leaves an already-expanded fieldset untouched", async () => {
      addFieldset();
      container.classList.remove("collapsed");
      await loadScript("assets/javascripts/shared/ai_helper_collapsible_fieldset");

      window.AiHelperCollapsibleFieldset.setExpanded("ai-helper-reply-fields", true);

      expect(container.classList.contains("collapsed")).toBe(false);
    });

    it("does nothing when the fieldset does not exist", async () => {
      await loadScript("assets/javascripts/shared/ai_helper_collapsible_fieldset");

      expect(() => window.AiHelperCollapsibleFieldset.setExpanded("nonexistent", true)).not.toThrow();
    });
  });

  describe("aiHelperSaveReplyState (window-exposed)", () => {
    it("saves replyExpanded: true when the fieldset is not collapsed", async () => {
      addFieldset({ userId: 42 });
      container.classList.remove("collapsed");
      await loadScript("assets/javascripts/shared/ai_helper_collapsible_fieldset");

      window.aiHelperSaveReplyState();

      expect(JSON.parse(localStorage.getItem("aiHelperReplyState_42"))).toEqual({ replyExpanded: true });
    });

    it("saves replyExpanded: false when the fieldset is collapsed", async () => {
      addFieldset({ userId: 42 });
      container.classList.add("collapsed");
      await loadScript("assets/javascripts/shared/ai_helper_collapsible_fieldset");

      window.aiHelperSaveReplyState();

      expect(JSON.parse(localStorage.getItem("aiHelperReplyState_42"))).toEqual({ replyExpanded: false });
    });
  });

  describe("ai_helper_generate_reply (window-exposed)", () => {
    it("delegates to ai_helper.generateReplyStream with the instructions and configured values", async () => {
      addFieldset({ generateReplyUrl: "/gen", errorMessage: "boom", applyLabel: "OK", copyIconHtml: "<i>c</i>" });
      const textarea = document.createElement("textarea");
      textarea.id = "ai-helper-reply-instructions";
      textarea.value = "please be nice";
      document.body.appendChild(textarea);
      await loadScript("assets/javascripts/shared/ai_helper_collapsible_fieldset");

      window.ai_helper_generate_reply(123);

      expect(aiHelperMock.generateReplyStream).toHaveBeenCalledWith("/gen", "please be nice", "boom", "OK", "<i>c</i>");
      textarea.remove();
    });
  });

  describe("state restore (DOMContentLoaded)", () => {
    it("expands the fieldset when a prior replyExpanded: true state is saved", async () => {
      addFieldset({ userId: 1 });
      localStorage.setItem("aiHelperReplyState_1", JSON.stringify({ replyExpanded: true }));

      const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/shared/ai_helper_collapsible_fieldset");

      expect(container.classList.contains("collapsed")).toBe(false);
      cleanup.removeRegisteredListeners();
    });

    it("collapses the fieldset when a prior replyExpanded: false state is saved", async () => {
      addFieldset({ userId: 1 });
      container.classList.remove("collapsed");
      localStorage.setItem("aiHelperReplyState_1", JSON.stringify({ replyExpanded: false }));

      const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/shared/ai_helper_collapsible_fieldset");

      expect(container.classList.contains("collapsed")).toBe(true);
      cleanup.removeRegisteredListeners();
    });

    it("leaves the fieldset untouched when no saved state exists", async () => {
      addFieldset({ userId: 2 });

      const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/shared/ai_helper_collapsible_fieldset");

      expect(container.classList.contains("collapsed")).toBe(true);
      cleanup.removeRegisteredListeners();
    });

    it("does nothing when the fieldset is absent", async () => {
      await expect(loadScriptAndFireDOMContentLoaded("assets/javascripts/shared/ai_helper_collapsible_fieldset")).resolves.toBeDefined();
    });
  });
});
