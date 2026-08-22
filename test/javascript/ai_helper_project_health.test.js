import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScriptAndFireDOMContentLoaded } from "./support/dom_content_loaded.js";
import { loadScript } from "./support/load_script.js";

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
    await loadScript("assets/javascripts/ai_helper_markdown_parser");
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
      if (finalContent) resultDiv.classList.add("ai-helper-final-content");
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
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_project_health");
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

  describe("generate report click delegation", () => {
    it("shows an error and does not stream when the result div is missing", async () => {
      addHealthContainer({ withResult: false });
      addGenerateLink();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
      const alertSpy = vi.fn();
      vi.stubGlobal("alert", alertSpy);

      await load();
      document.getElementById("ai-helper-generate-project-health-link").dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );

      expect(errorSpy).toHaveBeenCalled();
      expect(alertSpy).toHaveBeenCalled();
      expect(FakeEventSource.instances.length).toBe(0);
      errorSpy.mockRestore();
    });

    it("ignores clicks that are not on the generate link", async () => {
      addHealthContainer();
      await load();

      container.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(FakeEventSource.instances.length).toBe(0);
    });

    it("starts streaming, hides the placeholder, shows the report detail, and removes an existing PDF button", async () => {
      const { contentDiv, resultDiv } = addHealthContainer({ finalContent: true });
      const hiddenField = document.createElement("input");
      hiddenField.id = "ai-helper-health-report-content";
      hiddenField.value = "old content";
      container.appendChild(hiddenField);
      const link = addGenerateLink();
      const placeholder = document.createElement("div");
      placeholder.className = "ai-helper-detail-placeholder";
      container.appendChild(placeholder);
      const reportDetail = document.createElement("div");
      reportDetail.className = "ai-helper-health-report-detail";
      reportDetail.style.display = "none";
      container.appendChild(reportDetail);

      await load();
      expect(container.querySelector(".other-formats")).not.toBeNull();

      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(placeholder.style.display).toBe("none");
      expect(reportDetail.style.display).toBe("block");
      expect(resultDiv.innerHTML).toContain("ai-helper-loader");
      expect(contentDiv.classList.contains("has-report")).toBe(true);
      expect(container.querySelector(".other-formats")).toBeNull();
      expect(FakeEventSource.instances.length).toBe(1);
      expect(FakeEventSource.instances[0].url).toContain("/projects/1/ai_helper/project_health/generate");
    });

    it("closes a previous stream when the generate link is clicked again", async () => {
      addHealthContainer();
      const link = addGenerateLink();
      await load();

      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const first = FakeEventSource.instances[0];
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(first.closed).toBe(true);
      expect(FakeEventSource.instances.length).toBe(2);
    });

    it("streams content, finalizes on stop, stores the content, and refreshes metadata", async () => {
      addMeta("ai-helper-project-health-metadata-url", "/metadata");
      const { resultDiv } = addHealthContainer();
      const link = addGenerateLink();
      const fetchMock = vi.fn(async () => ({ status: 204 }));
      vi.stubGlobal("fetch", fetchMock);

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];

      source.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: "Report: " } }] }) });
      expect(resultDiv.innerHTML).toContain("Report:");
      expect(resultDiv.innerHTML).toContain("ai-helper-cursor");

      source.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: "good" } }] }) });
      source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });

      expect(source.closed).toBe(true);
      expect(resultDiv.innerHTML).toContain("ai-helper-final-content");
      expect(document.getElementById("ai-helper-health-report-content").value).toBe("Report: good");
      expect(container.querySelector(".other-formats")).not.toBeNull();

      await new Promise((resolve) => setTimeout(resolve, 0));
      expect(fetchMock).toHaveBeenCalled();
    });

    it("creates the hidden report-content field when it does not already exist", async () => {
      addHealthContainer();
      const link = addGenerateLink();
      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];

      expect(document.getElementById("ai-helper-health-report-content")).toBeNull();

      source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });

      expect(document.getElementById("ai-helper-health-report-content").value).toBe("");
    });

    it("ignores malformed SSE payloads without throwing", async () => {
      addHealthContainer();
      const link = addGenerateLink();
      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];

      expect(() => source.onmessage({ data: "not json" })).not.toThrow();
    });

    it("re-initializes master-detail history and selects the first report after streaming stops", async () => {
      addHealthContainer();
      const link = addGenerateLink();
      const historyRow = document.createElement("div");
      historyRow.className = "ai-helper-report-row";
      container.appendChild(historyRow);
      const masterDetailInstance = { selectedReportId: "old", selectReport: vi.fn() };
      const updateHealthReportHistory = vi.fn((callback) => callback(masterDetailInstance));
      window.updateHealthReportHistory = updateHealthReportHistory;

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];
      source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });

      // Real timers here: the production code chains a 1000ms and then a
      // 100ms setTimeout, and combining vi.useFakeTimers() with the
      // MutationObserver + EventSource stubs active in this suite reliably
      // hangs advanceTimersByTimeAsync, so we just wait for real.
      await new Promise((resolve) => setTimeout(resolve, 1100));
      expect(updateHealthReportHistory).toHaveBeenCalledTimes(1);

      await new Promise((resolve) => setTimeout(resolve, 150));
      expect(masterDetailInstance.selectedReportId).toBeNull();
      expect(masterDetailInstance.selectReport).toHaveBeenCalledWith(historyRow);
    }, 10000);

    it("refreshes metadata directly when updateHealthReportHistory yields no instance", async () => {
      addMeta("ai-helper-project-health-metadata-url", "/metadata");
      addMeta("ai-helper-project-health-created-label", "Created");
      addHealthContainer();
      const link = addGenerateLink();
      const updateHealthReportHistory = vi.fn((callback) => callback(null));
      window.updateHealthReportHistory = updateHealthReportHistory;
      const fetchMock = vi.fn(async () => ({ status: 204 }));
      vi.stubGlobal("fetch", fetchMock);

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      FakeEventSource.instances[0].onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });

      await new Promise((resolve) => setTimeout(resolve, 1100));

      expect(fetchMock).toHaveBeenCalledWith("/metadata", expect.objectContaining({ credentials: "same-origin" }));
    }, 10000);

    it("shows a translated error and removes the PDF button on stream error", async () => {
      addMeta("error-message", "Generation failed");
      const { contentDiv, resultDiv } = addHealthContainer({ finalContent: true });
      const hiddenField = document.createElement("input");
      hiddenField.id = "ai-helper-health-report-content";
      hiddenField.value = "content";
      container.appendChild(hiddenField);
      const link = addGenerateLink();
      await load();
      expect(container.querySelector(".other-formats")).not.toBeNull();

      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      FakeEventSource.instances[0].onerror();

      expect(resultDiv.innerHTML).toContain("Generation failed");
      expect(contentDiv.style.display).toBe("block");
      expect(container.querySelector(".other-formats")).toBeNull();
    });

    it("falls back to a generic error message on stream error without a meta tag", async () => {
      const { resultDiv } = addHealthContainer();
      const link = addGenerateLink();
      await load();

      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      FakeEventSource.instances[0].onerror();

      expect(resultDiv.innerHTML).toContain("Error");
    });
  });

  describe("metadata refresh", () => {
    it("does nothing when no metadata URL meta tag is present", async () => {
      addHealthContainer();
      const link = addGenerateLink();
      const fetchMock = vi.fn();
      vi.stubGlobal("fetch", fetchMock);

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      FakeEventSource.instances[0].onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(fetchMock).not.toHaveBeenCalled();
    });

    it("swallows fetch errors during metadata refresh", async () => {
      addMeta("ai-helper-project-health-metadata-url", "/metadata");
      const { resultDiv } = addHealthContainer();
      const link = addGenerateLink();
      vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("network down"); }));

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      await expect(
        (async () => {
          FakeEventSource.instances[0].onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });
          await new Promise((resolve) => setTimeout(resolve, 0));
        })(),
      ).resolves.toBeUndefined();
      expect(resultDiv.innerHTML).toContain("ai-helper-final-content");
    });

    it("renders the formatted created-on metadata next to the contextual actions", async () => {
      addMeta("ai-helper-project-health-metadata-url", "/metadata");
      addMeta("ai-helper-project-health-created-label", "Created on");
      const { healthDiv } = addHealthContainer();
      const contextual = document.createElement("div");
      contextual.className = "contextual";
      healthDiv.insertBefore(contextual, healthDiv.firstChild);
      const link = addGenerateLink();
      vi.stubGlobal(
        "fetch",
        vi.fn(async () => ({ status: 200, ok: true, json: async () => ({ created_on_formatted: "2026-01-01" }) })),
      );

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      FakeEventSource.instances[0].onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });
      await new Promise((resolve) => setTimeout(resolve, 0));

      const meta = document.getElementById("ai-helper-project-health-meta");
      expect(meta).not.toBeNull();
      expect(meta.previousElementSibling).toBe(contextual);
      expect(meta.textContent).toContain("Created on:");
      expect(meta.textContent).toContain("2026-01-01");
    });

    it("removes existing metadata when the server returns 204", async () => {
      addMeta("ai-helper-project-health-metadata-url", "/metadata");
      const { healthDiv } = addHealthContainer();
      const existingMeta = document.createElement("p");
      existingMeta.id = "ai-helper-project-health-meta";
      healthDiv.appendChild(existingMeta);
      const link = addGenerateLink();
      vi.stubGlobal("fetch", vi.fn(async () => ({ status: 204 })));

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      FakeEventSource.instances[0].onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(document.getElementById("ai-helper-project-health-meta")).toBeNull();
    });

    it("swallows a non-ok, non-204 metadata response", async () => {
      addMeta("ai-helper-project-health-metadata-url", "/metadata");
      addHealthContainer();
      const link = addGenerateLink();
      vi.stubGlobal("fetch", vi.fn(async () => ({ status: 500, ok: false })));

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      await expect(
        (async () => {
          FakeEventSource.instances[0].onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });
          await new Promise((resolve) => setTimeout(resolve, 0));
        })(),
      ).resolves.toBeUndefined();
    });
  });

  describe("export click delegation", () => {
    function setupExportableReport() {
      addHealthContainer({ finalContent: true });
      const hiddenField = document.createElement("input");
      hiddenField.id = "ai-helper-health-report-content";
      hiddenField.value = "exportable content";
      container.appendChild(hiddenField);
      return hiddenField;
    }

    it("submits a PDF export form for the static export link", async () => {
      addMeta("csrf-token", "tok-a");
      setupExportableReport();
      const pdfLink = document.createElement("a");
      pdfLink.id = "ai-helper-pdf-export-link";
      pdfLink.href = "/export.pdf";
      container.appendChild(pdfLink);
      await load();

      const submitSpy = vi.spyOn(HTMLFormElement.prototype, "submit").mockImplementation(() => {});
      const appendChildSpy = vi.spyOn(document.body, "appendChild");

      pdfLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      const form = appendChildSpy.mock.calls.find(([node]) => node.tagName === "FORM")?.[0];
      expect(form.action).toContain("/export.pdf");
      expect(form.querySelector('input[name="health_report_content"]').value).toBe("exportable content");
      expect(form.querySelector('input[name="authenticity_token"]').value).toBe("tok-a");
      expect(submitSpy).toHaveBeenCalledTimes(1);

      submitSpy.mockRestore();
      appendChildSpy.mockRestore();
    });

    it("submits a PDF export form for the dynamically-added export link", async () => {
      addMeta("csrf-token", "tok-b");
      setupExportableReport();
      await load();
      const pdfLink = container.querySelector("#ai-helper-pdf-export-link-dynamic");

      const submitSpy = vi.spyOn(HTMLFormElement.prototype, "submit").mockImplementation(() => {});
      const appendChildSpy = vi.spyOn(document.body, "appendChild");

      pdfLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(appendChildSpy.mock.calls.some(([node]) => node.tagName === "FORM")).toBe(true);
      expect(submitSpy).toHaveBeenCalledTimes(1);

      submitSpy.mockRestore();
      appendChildSpy.mockRestore();
    });

    it("submits a Markdown export form for the dynamically-added export link", async () => {
      addMeta("csrf-token", "tok-c");
      setupExportableReport();
      await load();
      const markdownLink = container.querySelector("#ai-helper-markdown-export-link-dynamic");

      const submitSpy = vi.spyOn(HTMLFormElement.prototype, "submit").mockImplementation(() => {});
      const appendChildSpy = vi.spyOn(document.body, "appendChild");

      markdownLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      const form = appendChildSpy.mock.calls.find(([node]) => node.tagName === "FORM")?.[0];
      expect(form.querySelector('input[name="health_report_content"]').value).toBe("exportable content");

      submitSpy.mockRestore();
      appendChildSpy.mockRestore();
    });

    it("does not build a form when the report content is empty", async () => {
      addHealthContainer({ finalContent: true });
      const hiddenField = document.createElement("input");
      hiddenField.id = "ai-helper-health-report-content";
      hiddenField.value = "";
      container.appendChild(hiddenField);
      await load();
      const pdfLink = document.createElement("a");
      pdfLink.id = "ai-helper-pdf-export-link";
      container.appendChild(pdfLink);

      const appendChildSpy = vi.spyOn(document.body, "appendChild");
      pdfLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(appendChildSpy.mock.calls.some(([node]) => node.tagName === "FORM")).toBe(false);
      appendChildSpy.mockRestore();
    });

    it("ignores clicks on unrelated elements", async () => {
      setupExportableReport();
      await load();

      const appendChildSpy = vi.spyOn(document.body, "appendChild");
      container.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(appendChildSpy.mock.calls.some(([node]) => node.tagName === "FORM")).toBe(false);
      appendChildSpy.mockRestore();
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
    await loadScript("assets/javascripts/ai_helper_markdown_parser");
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

    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_project_health");

    expect(resultDiv.innerHTML).toBe('<div class="ai-helper-final-content"><strong>bold report</strong></div>');
  });

  it("does nothing when the report content is empty", async () => {
    const { resultDiv, hiddenField } = addDetailPane();
    hiddenField.value = "";

    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_project_health");

    expect(resultDiv.innerHTML).toBe("");
  });

  it("submits a POST form with the Markdown content and CSRF token when the export link is clicked", async () => {
    const { exportLink } = addDetailPane({ markdownExportUrl: "/export-url" });
    const meta = el(document.createElement("meta"));
    meta.name = "csrf-token";
    meta.content = "test-token";
    document.head.appendChild(meta);

    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_project_health");

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
    await loadScript("assets/javascripts/ai_helper_markdown_parser");
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

    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_project_health");

    expect(resultDiv.innerHTML).toBe('<div class="ai-helper-final-content"><strong>bold report</strong></div>');
  });

  it("submits the pre-rendered export form when the export link is clicked", async () => {
    const { exportLink, exportForm } = addShowPage();

    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_project_health");

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

    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_project_health");

    expect(resultDiv.innerHTML).toBe("");
  });
});
