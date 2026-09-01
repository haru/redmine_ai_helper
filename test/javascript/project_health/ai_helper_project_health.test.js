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
    it("sets the loaded flag but wires nothing else when the markdown parser is unavailable", async () => {
      delete window.AiHelperMarkdownParser;
      addHealthContainer();
      addGenerateLink();

      await load();

      expect(window.aiHelperProjectHealthLoaded).toBe(true);
      document.getElementById("ai-helper-generate-project-health-link").dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );
      expect(FakeEventSource.instances.length).toBe(0);
    });
  });

  describe("existing report re-render on load", () => {
    it("re-parses stored markdown and adds the PDF export button", async () => {
      const { contentDiv, resultDiv } = addHealthContainer({ finalContent: true });
      const hiddenField = document.createElement("input");
      hiddenField.type = "hidden";
      hiddenField.id = "ai-helper-health-report-content";
      hiddenField.value = "**bold report**";
      container.appendChild(hiddenField);

      await load();

      expect(resultDiv.innerHTML).toContain("<strong>bold report</strong>");
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

// T042: characterization tests for project/_health_report_detail_pane.html.erb
// (T032) and project/_health_report_show.html.erb (T033) extraction.

describe("project/_health_report_detail_pane.html.erb extraction", () => {
  let cleanup;
  let elements;

  function el(node) {
    elements.push(node);
    return node;
  }

  beforeEach(async () => {
    elements = [];
    delete window.AiHelperMarkdownParser;
    delete window.aiHelperProjectHealthInitialized;
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
    await loadScript("assets/javascripts/project_health/ai_helper_project_health_actions");
  });

  afterEach(() => {
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    elements.forEach((node) => node.remove());
    vi.unstubAllGlobals();
  });

  function addDetailPane({ markdownExportUrl = "/projects/test/ai_helper/project_health_markdown" } = {}) {
    const detailPane = el(document.createElement("div"));
    detailPane.className = "ai-helper-health-report-detail";
    detailPane.dataset.config = JSON.stringify({ markdownExportUrl });
    document.body.appendChild(detailPane);

    const resultDiv = document.createElement("div");
    resultDiv.id = "ai-helper-project-health-result";
    detailPane.appendChild(resultDiv);

    const hiddenField = document.createElement("input");
    hiddenField.id = "ai-helper-health-report-content";
    hiddenField.value = "**bold report**";
    detailPane.appendChild(hiddenField);

    const exportLink = document.createElement("a");
    exportLink.id = "ai-helper-markdown-export-detail";
    detailPane.appendChild(exportLink);

    return { detailPane, resultDiv, hiddenField, exportLink };
  }

  it("re-parses the stored Markdown into the result div on load", async () => {
    const { resultDiv } = addDetailPane();

    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_health/ai_helper_project_health");

    expect(resultDiv.innerHTML).toBe('<div class="ai-helper-final-content"><strong>bold report</strong></div>');
  });

  it("does nothing when the report content is empty", async () => {
    const { resultDiv, hiddenField } = addDetailPane();
    hiddenField.value = "";

    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_health/ai_helper_project_health");

    expect(resultDiv.innerHTML).toBe("");
  });

  it("submits a POST form with the Markdown content and CSRF token when the export link is clicked", async () => {
    const { exportLink } = addDetailPane({ markdownExportUrl: "/export-url" });
    const meta = el(document.createElement("meta"));
    meta.name = "csrf-token";
    meta.content = "test-token";
    document.head.appendChild(meta);

    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_health/ai_helper_project_health");

    let submittedForm;
    const submitSpy = vi.spyOn(HTMLFormElement.prototype, "submit").mockImplementation(function () {
      submittedForm = this;
    });
    exportLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    expect(submittedForm.action).toContain("/export-url");
    expect(submittedForm.method).toBe("post");
    expect(submittedForm.elements["health_report_content"].value).toBe("**bold report**");
    expect(submittedForm.elements["authenticity_token"].value).toBe("test-token");
    submitSpy.mockRestore();
  });
});

describe("project/_health_report_show.html.erb extraction", () => {
  let cleanup;
  let elements;

  function el(node) {
    elements.push(node);
    return node;
  }

  beforeEach(async () => {
    elements = [];
    delete window.AiHelperMarkdownParser;
    delete window.aiHelperProjectHealthInitialized;
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
    await loadScript("assets/javascripts/project_health/ai_helper_project_health_actions");
  });

  afterEach(() => {
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    elements.forEach((node) => node.remove());
    vi.unstubAllGlobals();
  });

  function addShowPage() {
    const container = el(document.createElement("div"));
    document.body.appendChild(container);

    const resultDiv = document.createElement("div");
    resultDiv.id = "ai-helper-project-health-result";
    container.appendChild(resultDiv);

    const hiddenField = document.createElement("input");
    hiddenField.id = "ai-helper-health-report-content";
    hiddenField.value = "**bold report**";
    container.appendChild(hiddenField);

    const exportLink = document.createElement("a");
    exportLink.id = "export-markdown-link";
    container.appendChild(exportLink);

    const exportForm = document.createElement("form");
    exportForm.id = "markdown-export-form";
    container.appendChild(exportForm);

    return { resultDiv, hiddenField, exportLink, exportForm };
  }

  it("re-parses the stored Markdown into the result div on load", async () => {
    const { resultDiv } = addShowPage();

    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_health/ai_helper_project_health");

    expect(resultDiv.innerHTML).toBe('<div class="ai-helper-final-content"><strong>bold report</strong></div>');
  });

  it("submits the pre-rendered export form when the export link is clicked", async () => {
    const { exportLink, exportForm } = addShowPage();

    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_health/ai_helper_project_health");

    const submitSpy = vi.spyOn(exportForm, "submit").mockImplementation(() => {});
    exportLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    expect(submitSpy).toHaveBeenCalled();
    submitSpy.mockRestore();
  });

  it("does nothing when the hidden content field is absent", async () => {
    const container = el(document.createElement("div"));
    document.body.appendChild(container);
    const resultDiv = document.createElement("div");
    resultDiv.id = "ai-helper-project-health-result";
    container.appendChild(resultDiv);

    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_health/ai_helper_project_health");

    expect(resultDiv.innerHTML).toBe("");
  });
});
