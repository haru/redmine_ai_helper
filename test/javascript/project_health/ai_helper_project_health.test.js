import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScriptAndFireDOMContentLoaded } from "../support/dom_content_loaded.js";
import { loadScript } from "../support/load_script.js";

class FakeEventSource {
  constructor(url) {
    this.url = url;
    this.closed = false;
    this.onmessage = null;
    this.onerror = null;
    FakeEventSource.instances.push(this);
  }

  close() {
    this.closed = true;
  }
}
FakeEventSource.instances = [];

describe("ai_helper_project_health", () => {
  let container;
  let cleanup;

  beforeEach(async () => {
    container = document.createElement("div");
    document.body.appendChild(container);
    FakeEventSource.instances = [];
    vi.stubGlobal("EventSource", FakeEventSource);
    delete window.aiHelperProjectHealthInitialized;
    delete window.aiHelperProjectHealthLoaded;
    delete window.AiHelperMarkdownParser;
    delete window.updateHealthReportHistory;
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
  });

  afterEach(() => {
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    container.remove();
    document
      .querySelectorAll(
        'meta[name^="ai-helper-project-health"], meta[name="error-message"], meta[name="export-label"], ' +
          'meta[name="markdown-export-url"], meta[name="pdf-export-url"], meta[name="csrf-token"]',
      )
      .forEach((m) => m.remove());
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  function addMeta(name, content) {
    const meta = document.createElement("meta");
    meta.setAttribute("name", name);
    meta.setAttribute("content", content);
    document.head.appendChild(meta);
    return meta;
  }

  function addHealthContainer({ withResult = true, finalContent = false } = {}) {
    const healthDiv = document.createElement("div");
    healthDiv.className = "ai-helper-project-health";

    const contentDiv = document.createElement("div");
    contentDiv.className = "ai-helper-project-health-content";

    let resultDiv;
    if (withResult) {
      resultDiv = document.createElement("div");
      resultDiv.id = "ai-helper-project-health-result";
      if (finalContent) {resultDiv.classList.add("ai-helper-final-content");}
      contentDiv.appendChild(resultDiv);
    }

    healthDiv.appendChild(contentDiv);
    container.appendChild(healthDiv);

    return { healthDiv, contentDiv, resultDiv };
  }

  function addGenerateLink() {
    const link = document.createElement("a");
    link.id = "ai-helper-generate-project-health-link";
    link.href = "/projects/1/ai_helper/project_health/generate";
    container.appendChild(link);
    return link;
  }

  async function load() {
    await loadScript("assets/javascripts/project_health/ai_helper_project_health_actions");
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_health/ai_helper_project_health");
    return cleanup;
  }

  describe("initialization guards", () => {
    it("still initializes the existing report and then fails loudly when the markdown parser is unavailable", async () => {
      delete window.AiHelperMarkdownParser;
      const { contentDiv } = addHealthContainer({ finalContent: true });
      addGenerateLink();

      await expect(load()).rejects.toThrow(/AiHelperMarkdownParser/);

      expect(window.aiHelperProjectHealthLoaded).toBe(true);
      expect(contentDiv.classList.contains("has-report")).toBe(true);
      expect(container.querySelector(".other-formats")).not.toBeNull();
      document.getElementById("ai-helper-generate-project-health-link").dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );
      expect(FakeEventSource.instances.length).toBe(0);
    });
  });

  describe("existing report display on load", () => {
    it("keeps the server-rendered body unchanged and adds has-report plus the PDF export button", async () => {
      const { contentDiv, resultDiv } = addHealthContainer({ finalContent: true });
      // Distinctly server-rendered markup that the JS parser would never produce (it always emits a <thead>).
      const serverRenderedBody = '<table class="list"><tbody><tr><td>server rendered</td></tr></tbody></table>';
      resultDiv.innerHTML = serverRenderedBody;
      // The raw Markdown in the hidden field must NOT be re-parsed into the body.
      const hiddenField = document.createElement("input");
      hiddenField.type = "hidden";
      hiddenField.id = "ai-helper-health-report-content";
      hiddenField.value = "**bold report**";
      container.appendChild(hiddenField);

      await load();

      expect(resultDiv.innerHTML).toBe(serverRenderedBody);
      expect(contentDiv.classList.contains("has-report")).toBe(true);
      expect(container.querySelector(".other-formats")).not.toBeNull();
    });

    it("uses default export labels and URLs when no meta tags are present", async () => {
      addHealthContainer({ finalContent: true });
      const hiddenField = document.createElement("input");
      hiddenField.id = "ai-helper-health-report-content";
      hiddenField.value = "content";
      container.appendChild(hiddenField);

      await load();

      const otherFormats = container.querySelector(".other-formats");
      expect(otherFormats.innerHTML).toContain("Export to");
      expect(otherFormats.querySelector("#ai-helper-pdf-export-link-dynamic").getAttribute("href")).toBe("#");
    });

    it("uses export labels and URLs from meta tags when present", async () => {
      addMeta("export-label", "Exporter");
      addMeta("markdown-export-url", "/export.md");
      addMeta("pdf-export-url", "/export.pdf");
      addHealthContainer({ finalContent: true });
      const hiddenField = document.createElement("input");
      hiddenField.id = "ai-helper-health-report-content";
      hiddenField.value = "content";
      container.appendChild(hiddenField);

      await load();

      const otherFormats = container.querySelector(".other-formats");
      expect(otherFormats.innerHTML).toContain("Exporter");
      expect(otherFormats.querySelector("#ai-helper-pdf-export-link-dynamic").getAttribute("href")).toBe(
        "/export.pdf",
      );
      expect(otherFormats.querySelector("#ai-helper-markdown-export-link-dynamic").getAttribute("href")).toBe(
        "/export.md",
      );
    });

    it("does not touch the DOM when the result div lacks final-content styling", async () => {
      const { contentDiv } = addHealthContainer({ finalContent: false });

      await load();

      expect(contentDiv.classList.contains("has-report")).toBe(false);
      expect(container.querySelector(".other-formats")).toBeNull();
    });

    it("does nothing when there is no report container on the page", async () => {
      await expect(load()).resolves.toBeDefined();
    });
  });

  describe("MutationObserver re-initialization", () => {
    it("adds has-report and a PDF button when the report content is replaced dynamically", async () => {
      const { healthDiv, contentDiv } = addHealthContainer({ withResult: false });
      await load();

      const resultDiv = document.createElement("div");
      resultDiv.id = "ai-helper-project-health-result";
      resultDiv.classList.add("ai-helper-final-content");
      contentDiv.appendChild(resultDiv);

      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(contentDiv.classList.contains("has-report")).toBe(true);
      expect(healthDiv.querySelector(".other-formats")).not.toBeNull();
    });

    it("does not duplicate the PDF button when it already exists", async () => {
      const { healthDiv, contentDiv, resultDiv } = addHealthContainer({ finalContent: true });
      const hiddenField = document.createElement("input");
      hiddenField.id = "ai-helper-health-report-content";
      hiddenField.value = "content";
      container.appendChild(hiddenField);
      await load();
      expect(healthDiv.querySelectorAll(".other-formats").length).toBe(1);

      // Trigger an unrelated childList mutation under the observed container.
      const marker = document.createElement("span");
      contentDiv.appendChild(marker);
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(healthDiv.querySelectorAll(".other-formats").length).toBe(1);
      void resultDiv;
    });
  });
});
