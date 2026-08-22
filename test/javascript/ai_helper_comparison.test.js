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

describe("ai_helper_comparison", () => {
  let container;
  let cleanup;

  beforeEach(async () => {
    container = document.createElement("div");
    document.body.appendChild(container);
    FakeEventSource.instances = [];
    vi.stubGlobal("EventSource", FakeEventSource);
    delete window.aiHelperComparisonInitialized;
    delete window.AiHelperMarkdownParser;
    await loadScript("assets/javascripts/ai_helper_markdown_parser");
  });

  afterEach(() => {
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    container.remove();
    document.querySelectorAll('meta[name="i18n-error-message"], meta[name="csrf-token"]').forEach((m) => m.remove());
    vi.unstubAllGlobals();
  });

  function addMeta(name, content) {
    const meta = document.createElement("meta");
    meta.setAttribute("name", name);
    meta.setAttribute("content", content);
    document.head.appendChild(meta);
    return meta;
  }

  function addResultDiv({ analysisUrl = "/comparisons/1/analyze", omitAnalysisUrl = false } = {}) {
    const resultDiv = document.createElement("div");
    resultDiv.id = "ai-helper-comparison-analysis";
    if (!omitAnalysisUrl) resultDiv.dataset.analysisUrl = analysisUrl;
    container.appendChild(resultDiv);
    return resultDiv;
  }

  function addExportUi() {
    const exportDiv = document.createElement("div");
    exportDiv.id = "ai-helper-comparison-export";
    exportDiv.style.display = "none";

    const hiddenField = document.createElement("input");
    hiddenField.type = "hidden";
    hiddenField.id = "ai-helper-comparison-content";

    const oldReportIdField = document.createElement("input");
    oldReportIdField.id = "ai-helper-comparison-old-report-id";
    oldReportIdField.value = "10";

    const newReportIdField = document.createElement("input");
    newReportIdField.id = "ai-helper-comparison-new-report-id";
    newReportIdField.value = "11";

    const pdfLink = document.createElement("a");
    pdfLink.id = "ai-helper-comparison-pdf-export-link";
    pdfLink.href = "/comparisons/1/export.pdf";

    const markdownLink = document.createElement("a");
    markdownLink.id = "ai-helper-comparison-markdown-export-link";
    markdownLink.href = "/comparisons/1/export.md";

    container.append(exportDiv, hiddenField, oldReportIdField, newReportIdField, pdfLink, markdownLink);
    return { exportDiv, hiddenField, oldReportIdField, newReportIdField, pdfLink, markdownLink };
  }

  async function load() {
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_comparison");
    return cleanup;
  }

  it("does nothing when the analysis container is absent", async () => {
    await expect(load()).resolves.toBeDefined();
    expect(FakeEventSource.instances.length).toBe(0);
  });

  it("does nothing when the analysis container has no analysis URL", async () => {
    addResultDiv({ omitAnalysisUrl: true });

    await load();

    expect(FakeEventSource.instances.length).toBe(0);
  });

  it("does nothing when the markdown parser is unavailable", async () => {
    delete window.AiHelperMarkdownParser;
    addResultDiv();

    await load();

    expect(FakeEventSource.instances.length).toBe(0);
  });

  it("starts streaming analysis automatically and finalizes on stop", async () => {
    const resultDiv = addResultDiv();
    const { exportDiv, hiddenField } = addExportUi();
    exportDiv.style.display = "none";

    await load();

    expect(FakeEventSource.instances.length).toBe(1);
    const source = FakeEventSource.instances[0];
    expect(source.url).toBe("/comparisons/1/analyze");
    expect(resultDiv.innerHTML).toContain("ai-helper-loader");

    source.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: "Analysis: " } }] }) });
    expect(resultDiv.innerHTML).toContain("Analysis:");
    expect(resultDiv.innerHTML).toContain("ai-helper-cursor");

    source.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: "better" } }] }) });
    source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });

    expect(resultDiv.innerHTML).toContain("ai-helper-final-content");
    expect(resultDiv.innerHTML).toContain("Analysis: better");
    expect(hiddenField.value).toBe("Analysis: better");
    expect(exportDiv.style.display).toBe("block");
    expect(source.closed).toBe(true);
  });

  it("ignores malformed SSE payloads without throwing", async () => {
    const resultDiv = addResultDiv();
    addExportUi();

    await load();
    const source = FakeEventSource.instances[0];

    expect(() => source.onmessage({ data: "not json" })).not.toThrow();
    expect(resultDiv.innerHTML).toContain("ai-helper-loader");
  });

  it("shows a translated error message and closes the stream on error", async () => {
    addMeta("i18n-error-message", "Analysis failed");
    const resultDiv = addResultDiv();
    addExportUi();

    await load();
    const source = FakeEventSource.instances[0];

    source.onerror();

    expect(resultDiv.innerHTML).toContain("Analysis failed");
    expect(source.closed).toBe(true);
  });

  it("falls back to a generic error message when no translation meta tag is present", async () => {
    const resultDiv = addResultDiv();
    addExportUi();

    await load();
    const source = FakeEventSource.instances[0];

    source.onerror();

    expect(resultDiv.innerHTML).toContain("Error");
  });

  it("submits a PDF export form with the streamed content and CSRF token", async () => {
    addMeta("csrf-token", "test-token");
    addResultDiv();
    const { pdfLink, hiddenField, oldReportIdField, newReportIdField } = addExportUi();

    await load();
    const source = FakeEventSource.instances[0];
    source.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: "content" } }] }) });
    source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });
    expect(hiddenField.value).toBe("content");

    const submitSpy = vi.spyOn(HTMLFormElement.prototype, "submit").mockImplementation(() => {});
    const appendChildSpy = vi.spyOn(document.body, "appendChild");

    pdfLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    const capturedForm = appendChildSpy.mock.calls.find(([node]) => node.tagName === "FORM")?.[0];
    expect(capturedForm.action).toContain("/comparisons/1/export.pdf");
    expect(capturedForm.method.toLowerCase()).toBe("post");
    expect(capturedForm.querySelector('input[name="comparison_content"]').value).toBe("content");
    expect(capturedForm.querySelector('input[name="old_report_id"]').value).toBe(oldReportIdField.value);
    expect(capturedForm.querySelector('input[name="new_report_id"]').value).toBe(newReportIdField.value);
    expect(capturedForm.querySelector('input[name="authenticity_token"]').value).toBe("test-token");
    expect(submitSpy).toHaveBeenCalledTimes(1);

    submitSpy.mockRestore();
    appendChildSpy.mockRestore();
  });

  it("submits a Markdown export form and omits the CSRF value when the meta tag is absent", async () => {
    addResultDiv();
    const { markdownLink } = addExportUi();

    await load();
    const source = FakeEventSource.instances[0];
    source.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: "md" } }] }) });
    source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });

    const submitSpy = vi.spyOn(HTMLFormElement.prototype, "submit").mockImplementation(() => {});
    const appendChildSpy = vi.spyOn(document.body, "appendChild");

    markdownLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    const capturedForm = appendChildSpy.mock.calls.find(([node]) => node.tagName === "FORM")?.[0];
    expect(capturedForm.action).toContain("/comparisons/1/export.md");
    expect(capturedForm.querySelector('input[name="authenticity_token"]').value).toBe("");
    expect(submitSpy).toHaveBeenCalledTimes(1);

    submitSpy.mockRestore();
    appendChildSpy.mockRestore();
  });

  it("does not build an export form when there is no streamed content yet", async () => {
    addResultDiv();
    const { pdfLink } = addExportUi();

    await load();

    const appendChildSpy = vi.spyOn(document.body, "appendChild");
    pdfLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    expect(appendChildSpy.mock.calls.some(([node]) => node.tagName === "FORM")).toBe(false);
    appendChildSpy.mockRestore();
  });

  it("ignores clicks that are not on an export link", async () => {
    addResultDiv();
    addExportUi();

    await load();

    const appendChildSpy = vi.spyOn(document.body, "appendChild");
    container.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    expect(appendChildSpy.mock.calls.some(([node]) => node.tagName === "FORM")).toBe(false);
    appendChildSpy.mockRestore();
  });
});
