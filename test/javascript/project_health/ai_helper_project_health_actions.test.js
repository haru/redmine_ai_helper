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

describe("ai_helper_project_health_actions", () => {
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
