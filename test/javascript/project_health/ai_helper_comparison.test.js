import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScriptAndFireDOMContentLoaded } from "../support/dom_content_loaded.js";
import { stubAnimationFrames } from "../support/animation_frames.js";
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

describe("ai_helper_comparison", () => {
  let container;
  let cleanup;
  let frames;

  function sendChunk(source, text) {
    source.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: text } }] }) });
  }

  beforeEach(async () => {
    container = document.createElement("div");
    document.body.appendChild(container);
    FakeEventSource.instances = [];
    vi.stubGlobal("EventSource", FakeEventSource);
    delete window.aiHelperComparisonInitialized;
    delete window.AiHelperMarkdownParser;
    delete window.AiHelperChartDirective;
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
    await loadScript("assets/javascripts/project_health/ai_helper_chart_directive");
    await loadScript("assets/javascripts/shared/ai_helper_frame_renderer");
    frames = stubAnimationFrames();
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

  function addResultDiv({ analysisUrl = "/comparisons/1/analyze", omitAnalysisUrl = false, chartMessage = "Charts unavailable" } = {}) {
    const resultDiv = document.createElement("div");
    resultDiv.id = "ai-helper-comparison-analysis";
    resultDiv.dataset.chartUnavailableMessage = chartMessage;
    if (!omitAnalysisUrl) {resultDiv.dataset.analysisUrl = analysisUrl;}
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
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_health/ai_helper_comparison");
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

    sendChunk(source, "Analysis: ");
    frames.flush();
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

  it("replaces chart directives with the unavailable message before parsing, while streaming and at the end", async () => {
    const resultDiv = addResultDiv({ chartMessage: "NO-CHARTS-HERE" });
    const { hiddenField } = addExportUi();
    const replaceSpy = vi.spyOn(window.AiHelperChartDirective, "replaceForComparison");

    await load();
    const source = FakeEventSource.instances[0];
    const body = "Intro\n\n{{ai_helper_chart(status, version=12)}}\n\nOutro";

    sendChunk(source, body);
    frames.flush();
    expect(replaceSpy).toHaveBeenCalledWith(body, "NO-CHARTS-HERE");
    expect(resultDiv.innerHTML).toContain("NO-CHARTS-HERE");
    expect(resultDiv.innerHTML).not.toContain("ai_helper_chart");

    source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });
    expect(resultDiv.innerHTML).toContain("NO-CHARTS-HERE");
    expect(resultDiv.innerHTML).not.toContain("ai_helper_chart");
    // The export keeps the raw body; the server replaces the directives.
    expect(hiddenField.value).toBe(body);
    replaceSpy.mockRestore();
  });

  it("throws when the chart unavailable message is missing", async () => {
    const resultDiv = addResultDiv();
    delete resultDiv.dataset.chartUnavailableMessage;
    addExportUi();

    await load();
    const source = FakeEventSource.instances[0];
    sendChunk(source, "text");

    expect(() => frames.flush()).toThrow(TypeError);

    // The final frame is no longer guarded by the bare catch either: a
    // render failure there must surface instead of leaving the cursor
    // frame stuck without exports or console output (CRF-047).
    expect(() => source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) })).toThrow(TypeError);
    expect(resultDiv.innerHTML).not.toContain("ai-helper-final-content");
    expect(source.closed).toBe(true);
  });

  it("coalesces chunks that arrive within one animation frame into a single render", async () => {
    const resultDiv = addResultDiv();
    addExportUi();
    const parseSpy = vi.spyOn(window.AiHelperMarkdownParser.prototype, "parse");

    await load();
    const source = FakeEventSource.instances[0];

    sendChunk(source, "one ");
    sendChunk(source, "two ");
    sendChunk(source, "three");

    expect(parseSpy).not.toHaveBeenCalled();
    expect(resultDiv.innerHTML).toContain("ai-helper-loader");
    expect(frames.pendingCount()).toBe(1);

    frames.flush();

    expect(parseSpy).toHaveBeenCalledTimes(1);
    expect(parseSpy).toHaveBeenCalledWith("one two three");
    expect(resultDiv.innerHTML).toContain("one two three");
    parseSpy.mockRestore();
  });

  it("cancels a pending streaming render when the stream finishes", async () => {
    const resultDiv = addResultDiv();
    addExportUi();

    await load();
    const source = FakeEventSource.instances[0];

    sendChunk(source, "final text");
    source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });

    expect(frames.pendingCount()).toBe(0);
    expect(resultDiv.innerHTML).toContain("ai-helper-final-content");
    expect(resultDiv.innerHTML).not.toContain("ai-helper-cursor");
  });

  it("cancels a pending streaming render when the stream errors", async () => {
    const resultDiv = addResultDiv();
    addExportUi();

    await load();
    const source = FakeEventSource.instances[0];

    sendChunk(source, "partial");
    source.onerror();

    expect(frames.pendingCount()).toBe(0);
    expect(resultDiv.innerHTML).toContain("ai-helper-error");
  });

  it("logs a malformed SSE payload as a parse failure and keeps receiving", async () => {
    const resultDiv = addResultDiv();
    addExportUi();
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});

    await load();
    const source = FakeEventSource.instances[0];

    expect(() => source.onmessage({ data: "not json" })).not.toThrow();
    expect(consoleError).toHaveBeenCalledWith(
      "Failed to parse comparison streaming event data:",
      expect.any(SyntaxError),
      "not json",
    );
    expect(resultDiv.innerHTML).toContain("ai-helper-loader");
    consoleError.mockRestore();
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
