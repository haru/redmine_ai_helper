import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "./support/load_script.js";
import { loadScriptAndFireDOMContentLoaded } from "./support/dom_content_loaded.js";

// T038: characterization tests for wiki/_summary.html.erb extraction.

describe("ai_helper_wiki_summary", () => {
  let fieldset;
  let aiHelperMock;

  function addFieldset(config = {}) {
    fieldset = document.createElement("fieldset");
    fieldset.id = "ai-helper-wiki-summary-fields";
    fieldset.className = "collapsible collapsed";
    const legend = document.createElement("legend");
    fieldset.appendChild(legend);
    fieldset.dataset.config = JSON.stringify({
      summaryUrl: "/projects/test/ai_helper/wiki/Foo/summary",
      generateUrl: "/projects/test/ai_helper/wiki/Foo/generate_summary",
      errorMessage: "Error occurred",
      userId: 7,
      hasSummary: false,
      ...config,
    });
    document.body.appendChild(fieldset);
    return fieldset;
  }

  beforeEach(() => {
    aiHelperMock = { generateWikiSummaryStream: vi.fn() };
    vi.stubGlobal("ai_helper", aiHelperMock);
    vi.stubGlobal("toggleFieldset", vi.fn((legend) => {
      legend.closest("fieldset").classList.toggle("collapsed");
    }));
    // Real dependency lives in ai_helper_collapsible_fieldset.js (loaded
    // separately in production via html_header); stub an equivalent here.
    vi.stubGlobal("AiHelperCollapsibleFieldset", {
      setExpanded(fieldsetId, flag) {
        const el = document.getElementById(fieldsetId);
        if (!el) return;
        const legend = el.querySelector("legend");
        const isOpen = !el.classList.contains("collapsed");
        if (isOpen !== flag) {
          toggleFieldset(legend);
        }
      },
    });
  });

  afterEach(() => {
    fieldset?.remove();
    fieldset = undefined;
    vi.unstubAllGlobals();
    localStorage.clear();
    delete window.getWikiSummary;
    delete window.aiHelperSaveWikiSummaryState;
  });

  describe("getWikiSummary", () => {
    it("shows a loader, then renders the response on success", async () => {
      addFieldset();
      const summaryArea = document.createElement("div");
      summaryArea.id = "ai-helper-wiki-summary-area";
      document.body.appendChild(summaryArea);

      let createdInstance;
      function MockXHR() {
        this.open = vi.fn();
        this.send = vi.fn(() => {
          expect(summaryArea.innerHTML).toContain("ai-helper-loader");
        });
        this.onload = null;
        this.onerror = null;
        createdInstance = this;
      }
      vi.stubGlobal("XMLHttpRequest", MockXHR);

      await loadScript("assets/javascripts/ai_helper_wiki_summary");
      window.getWikiSummary();

      expect(createdInstance.open).toHaveBeenCalledWith("GET", "/projects/test/ai_helper/wiki/Foo/summary", true);

      createdInstance.status = 200;
      createdInstance.responseText = "<p>summary</p>";
      createdInstance.onload();

      expect(summaryArea.innerHTML).toBe("<p>summary</p>");
      summaryArea.remove();
    });

    it("appends ?update=true when update is requested", async () => {
      addFieldset();
      let createdInstance;
      function MockXHR() {
        this.open = vi.fn();
        this.send = vi.fn();
        createdInstance = this;
      }
      vi.stubGlobal("XMLHttpRequest", MockXHR);

      await loadScript("assets/javascripts/ai_helper_wiki_summary");
      window.getWikiSummary(true);

      expect(createdInstance.open).toHaveBeenCalledWith("GET", "/projects/test/ai_helper/wiki/Foo/summary?update=true", true);
    });

    it("shows an error message with status text on a non-200 response", async () => {
      addFieldset();
      const summaryArea = document.createElement("div");
      summaryArea.id = "ai-helper-wiki-summary-area";
      document.body.appendChild(summaryArea);

      let createdInstance;
      function MockXHR() {
        this.open = vi.fn();
        this.send = vi.fn();
        createdInstance = this;
      }
      vi.stubGlobal("XMLHttpRequest", MockXHR);

      await loadScript("assets/javascripts/ai_helper_wiki_summary");
      window.getWikiSummary();
      createdInstance.status = 500;
      createdInstance.statusText = "Internal Server Error";
      createdInstance.onload();

      expect(summaryArea.innerHTML).toBe('<div class="error">Error occurred: Internal Server Error</div>');
      summaryArea.remove();
    });

    it("shows an error message on network error", async () => {
      addFieldset();
      const summaryArea = document.createElement("div");
      summaryArea.id = "ai-helper-wiki-summary-area";
      document.body.appendChild(summaryArea);

      let createdInstance;
      function MockXHR() {
        this.open = vi.fn();
        this.send = vi.fn();
        createdInstance = this;
      }
      vi.stubGlobal("XMLHttpRequest", MockXHR);

      await loadScript("assets/javascripts/ai_helper_wiki_summary");
      window.getWikiSummary();
      createdInstance.onerror();

      expect(summaryArea.innerHTML).toBe('<div class="error">Error occurred</div>');
      summaryArea.remove();
    });

    it("does nothing when the fieldset is absent", async () => {
      await loadScript("assets/javascripts/ai_helper_wiki_summary");
      expect(() => window.getWikiSummary()).not.toThrow();
    });
  });

  describe("generateWikiSummaryStream", () => {
    it("delegates to ai_helper.generateWikiSummaryStream with the configured URL and error message, via the button click wired up on load", async () => {
      addFieldset({ generateUrl: "/gen-url", errorMessage: "boom" });
      const button = document.createElement("a");
      button.className = "ai-helper-wiki-summary-button";
      document.body.appendChild(button);

      const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_wiki_summary");
      button.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(aiHelperMock.generateWikiSummaryStream).toHaveBeenCalledWith("/gen-url", "boom");
      cleanup.removeRegisteredListeners();
      button.remove();
    });
  });

  describe("aiHelperSaveWikiSummaryState (window-exposed)", () => {
    it("saves 'expanded' to localStorage when the fieldset is not collapsed", async () => {
      addFieldset({ userId: 42 });
      fieldset.classList.remove("collapsed");
      await loadScript("assets/javascripts/ai_helper_wiki_summary");

      window.aiHelperSaveWikiSummaryState();

      expect(localStorage.getItem("aiHelperWikiSummaryState_42")).toBe("expanded");
    });

    it("saves 'collapsed' to localStorage when the fieldset is collapsed", async () => {
      addFieldset({ userId: 42 });
      fieldset.classList.add("collapsed");
      await loadScript("assets/javascripts/ai_helper_wiki_summary");

      window.aiHelperSaveWikiSummaryState();

      expect(localStorage.getItem("aiHelperWikiSummaryState_42")).toBe("collapsed");
    });
  });

  describe("initWikiSummary (DOMContentLoaded)", () => {
    it("moves the fieldset to the top of the wiki content and shows it", async () => {
      addFieldset();
      const contentDiv = document.createElement("div");
      contentDiv.id = "content";
      const wikiDiv = document.createElement("div");
      wikiDiv.className = "wiki";
      contentDiv.appendChild(wikiDiv);
      contentDiv.appendChild(fieldset);
      document.body.appendChild(contentDiv);

      const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_wiki_summary");

      expect(wikiDiv.previousElementSibling).toBe(fieldset);
      expect(fieldset.style.display).toBe("block");
      cleanup.removeRegisteredListeners();
      contentDiv.remove();
    });

    it("expands the fieldset when a prior 'expanded' state is saved", async () => {
      addFieldset({ userId: 1 });
      localStorage.setItem("aiHelperWikiSummaryState_1", "expanded");

      const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_wiki_summary");

      expect(fieldset.classList.contains("collapsed")).toBe(false);
      cleanup.removeRegisteredListeners();
    });

    it("keeps the fieldset collapsed when no saved state exists", async () => {
      addFieldset({ userId: 2 });

      const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_wiki_summary");

      expect(fieldset.classList.contains("collapsed")).toBe(true);
      cleanup.removeRegisteredListeners();
    });

    it("auto-loads the summary when hasSummary is true", async () => {
      addFieldset({ hasSummary: true, summaryUrl: "/auto-load" });
      let createdInstance;
      function MockXHR() {
        this.open = vi.fn();
        this.send = vi.fn();
        createdInstance = this;
      }
      vi.stubGlobal("XMLHttpRequest", MockXHR);

      const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_wiki_summary");

      expect(createdInstance.open).toHaveBeenCalledWith("GET", "/auto-load", true);
      cleanup.removeRegisteredListeners();
    });

    it("does not auto-load the summary when hasSummary is false", async () => {
      addFieldset({ hasSummary: false });
      const xhrSpy = vi.fn();
      vi.stubGlobal("XMLHttpRequest", xhrSpy);

      const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_wiki_summary");

      expect(xhrSpy).not.toHaveBeenCalled();
      cleanup.removeRegisteredListeners();
    });

    it("does nothing when the fieldset is absent", async () => {
      await expect(loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_wiki_summary")).resolves.toBeDefined();
    });
  });
});
