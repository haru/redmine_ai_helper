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

describe("ai_helper_project_health_actions", () => {
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
    frames = stubAnimationFrames();
    delete window.aiHelperProjectHealthInitialized;
    delete window.aiHelperProjectHealthLoaded;
    delete window.AiHelperMarkdownParser;
    delete window.updateHealthReportHistory;
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
    await loadScript("assets/javascripts/shared/ai_helper_frame_renderer");
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

  // Local DOM helper reproducing the dashboard detail pane structure of
  // app/views/ai_helper/project/_health_report_body.html.erb:26-29: a
  // selected report's pane has NO `.ai-helper-project-health` wrapper; the
  // result area sits inside `.ai-helper-health-report-view`, which sits
  // inside `.ai-helper-project-health-content`.
  function addDashboardDetailPane({ withResult = true } = {}) {
    const detailPane = document.createElement("div");
    detailPane.className = "ai-helper-health-report-body";

    const contentDiv = document.createElement("div");
    contentDiv.className = "ai-helper-project-health-content has-report";

    const viewDiv = document.createElement("div");
    viewDiv.className = "ai-helper-health-report-view";

    let resultDiv;
    if (withResult) {
      resultDiv = document.createElement("div");
      resultDiv.id = "ai-helper-project-health-result";
      viewDiv.appendChild(resultDiv);
    }

    contentDiv.appendChild(viewDiv);
    detailPane.appendChild(contentDiv);
    container.appendChild(detailPane);

    return { detailPane, contentDiv, resultDiv };
  }

  // Local DOM helper reproducing the dashboard detail pane of
  // app/views/ai_helper/project/_health_report_body.html.erb while an
  // edited report's ORIGINAL body is being viewed: the result area is
  // hidden and the pane still shows the previous report's metadata, edit
  // UI, flash notice, and export links — the elements data-model.md lists
  // as removed when a new generation starts.
  function addDetailPaneWithPreviousReport() {
    const detailPane = document.createElement("div");
    detailPane.className = "ai-helper-health-report-body";

    const flash = document.createElement("div");
    flash.className = "flash notice";
    flash.textContent = "saved";
    detailPane.appendChild(flash);

    const meta = document.createElement("div");
    meta.className = "ai-helper-health-report-meta";
    meta.textContent = "created";
    detailPane.appendChild(meta);

    const contextual = document.createElement("div");
    contextual.className = "contextual";
    detailPane.appendChild(contextual);

    const contentDiv = document.createElement("div");
    contentDiv.className = "ai-helper-project-health-content has-report";

    const viewDiv = document.createElement("div");
    viewDiv.className = "ai-helper-health-report-view";

    const resultDiv = document.createElement("div");
    resultDiv.id = "ai-helper-project-health-result";
    resultDiv.textContent = "current body";
    resultDiv.hidden = true; // "original report" view state
    viewDiv.appendChild(resultDiv);

    const original = document.createElement("div");
    original.className = "ai-helper-health-report-original";
    original.textContent = "original body";
    viewDiv.appendChild(original);

    const toggleParagraph = document.createElement("p");
    const showOriginal = document.createElement("a");
    showOriginal.className = "ai-helper-health-report-show-original";
    showOriginal.href = "#";
    toggleParagraph.appendChild(showOriginal);
    viewDiv.appendChild(toggleParagraph);

    const editForm = document.createElement("form");
    editForm.className = "ai-helper-health-report-edit-form";
    contentDiv.appendChild(viewDiv);
    contentDiv.appendChild(editForm);
    detailPane.appendChild(contentDiv);

    const otherFormats = document.createElement("p");
    otherFormats.className = "other-formats";
    detailPane.appendChild(otherFormats);

    container.appendChild(detailPane);

    return { detailPane, contentDiv, resultDiv };
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
      const { contentDiv, resultDiv } = addHealthContainer();
      const link = addGenerateLink();
      const fetchMock = vi.fn(async () => ({ status: 204 }));
      vi.stubGlobal("fetch", fetchMock);

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];

      sendChunk(source, "Report: ");
      frames.flush();
      expect(resultDiv.innerHTML).toContain("Report:");
      expect(resultDiv.innerHTML).toContain("ai-helper-cursor");

      sendChunk(source, "good");
      source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });

      expect(source.closed).toBe(true);
      expect(resultDiv.innerHTML).toContain("ai-helper-final-content");
      expect(document.getElementById("ai-helper-health-report-content").value).toBe("Report: good");
      expect(document.getElementById("ai-helper-health-report-content").parentElement).toBe(contentDiv);
      expect(container.querySelector(".other-formats")).not.toBeNull();

      await new Promise((resolve) => setTimeout(resolve, 0));
      expect(fetchMock).toHaveBeenCalled();
    });

    it("coalesces chunks that arrive within one animation frame into a single render", async () => {
      const { resultDiv } = addHealthContainer();
      const link = addGenerateLink();
      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];
      const renderSpy = vi.spyOn(window, "appendStreamingChunk");

      sendChunk(source, "one ");
      sendChunk(source, "two ");
      sendChunk(source, "three");

      expect(renderSpy).not.toHaveBeenCalled();
      expect(resultDiv.innerHTML).toContain("ai-helper-loader");
      expect(frames.pendingCount()).toBe(1);

      frames.flush();

      expect(renderSpy).toHaveBeenCalledTimes(1);
      expect(renderSpy.mock.calls[0][2]).toBe("one two three");
      expect(resultDiv.innerHTML).toContain("one two three");

      sendChunk(source, " four");
      frames.flush();

      expect(renderSpy).toHaveBeenCalledTimes(2);
      expect(renderSpy.mock.calls[1][2]).toBe("one two three four");
      renderSpy.mockRestore();
    });

    it("cancels a pending streaming render when the stream finishes", async () => {
      const { resultDiv } = addHealthContainer();
      const link = addGenerateLink();
      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];

      sendChunk(source, "final text");
      source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });

      expect(frames.pendingCount()).toBe(0);
      expect(resultDiv.innerHTML).toContain("ai-helper-final-content");
      expect(resultDiv.innerHTML).toContain("final text");
      expect(resultDiv.innerHTML).not.toContain("ai-helper-cursor");
    });

    it("drops a pending render from a stream replaced by a newer generation", async () => {
      const { resultDiv } = addHealthContainer();
      const link = addGenerateLink();
      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      sendChunk(FakeEventSource.instances[0], "stale text");

      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      frames.flush();

      expect(resultDiv.innerHTML).toContain("ai-helper-loader");
      expect(resultDiv.innerHTML).not.toContain("stale text");
    });

    it("cancels a pending streaming render when the stream errors", async () => {
      const { resultDiv } = addHealthContainer();
      const link = addGenerateLink();
      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];

      sendChunk(source, "partial");
      source.onerror();

      expect(frames.pendingCount()).toBe(0);
      expect(resultDiv.innerHTML).toContain("ai-helper-error");
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

    it("keeps one hidden field and one export link pair after two consecutive overview generations", async () => {
      const { contentDiv, healthDiv } = addHealthContainer();
      const link = addGenerateLink();

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const first = FakeEventSource.instances[0];
      first.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: "first" } }] }) });
      first.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });

      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const second = FakeEventSource.instances[1];
      second.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: "second" } }] }) });
      second.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });

      expect(contentDiv.querySelectorAll("#ai-helper-health-report-content").length).toBe(1);
      expect(document.getElementById("ai-helper-health-report-content").value).toBe("second");
      expect(healthDiv.querySelectorAll(".other-formats").length).toBe(1);
    });

    it("logs a parse failure and keeps receiving after a malformed SSE payload", async () => {
      const { resultDiv } = addHealthContainer();
      const link = addGenerateLink();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];

      expect(() => source.onmessage({ data: "not json" })).not.toThrow();
      expect(errorSpy).toHaveBeenCalledWith(
        "Failed to parse project health streaming event data:",
        expect.any(SyntaxError),
        "not json",
      );

      sendChunk(source, "after malformed");
      source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });
      frames.flush();

      expect(resultDiv.innerHTML).toContain("after malformed");
      expect(resultDiv.innerHTML).toContain("ai-helper-final-content");
      errorSpy.mockRestore();
    });

    it("propagates finalize errors out of onmessage without logging a parse failure", async () => {
      addHealthContainer();
      const link = addGenerateLink();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];
      const originalFinalize = window.finalizeStreamingContent;
      window.finalizeStreamingContent = vi.fn(() => {
        throw new Error("finalize boom");
      });

      expect(() =>
        source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) }),
      ).toThrow("finalize boom");
      expect(errorSpy).not.toHaveBeenCalled();

      errorSpy.mockRestore();
      window.finalizeStreamingContent = originalFinalize;
    });

    it("re-throws non-SyntaxError failures raised while parsing the payload", async () => {
      addHealthContainer();
      const link = addGenerateLink();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];

      const boom = new TypeError("data access failed");
      expect(() =>
        source.onmessage({
          get data() {
            throw boom;
          },
        }),
      ).toThrow(boom);
      expect(errorSpy).not.toHaveBeenCalled();

      errorSpy.mockRestore();
    });

    it("updates the master-detail history and selects the first report row when generation finishes in the dashboard detail pane", async () => {
      addDashboardDetailPane();
      const link = addGenerateLink();
      const historyRow = document.createElement("div");
      historyRow.className = "ai-helper-report-row";
      container.appendChild(historyRow);
      const masterDetailInstance = { selectedReportId: "old", selectReport: vi.fn() };
      window.updateHealthReportHistory = vi.fn((callback) => callback(masterDetailInstance));

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];
      source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });

      // Real timers here: the production code chains a 1000ms and then a
      // 100ms setTimeout (see the project-overview variant below for why
      // fake timers are not used in this suite).
      await new Promise((resolve) => setTimeout(resolve, 1100));
      expect(window.updateHealthReportHistory).toHaveBeenCalledTimes(1);

      await new Promise((resolve) => setTimeout(resolve, 150));
      expect(masterDetailInstance.selectedReportId).toBeNull();
      expect(masterDetailInstance.selectReport).toHaveBeenCalledWith(historyRow);
    }, 10000);

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

    it("removes the previous report's details from the detail pane and un-hides the result area when generation starts", async () => {
      const { detailPane, resultDiv } = addDetailPaneWithPreviousReport();
      const link = addGenerateLink();

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(detailPane.querySelector(".ai-helper-health-report-meta")).toBeNull();
      expect(detailPane.querySelector(".contextual")).toBeNull();
      expect(detailPane.querySelector(".ai-helper-health-report-edit-form")).toBeNull();
      expect(detailPane.querySelector(".ai-helper-health-report-original")).toBeNull();
      expect(detailPane.querySelector(".ai-helper-health-report-show-original")).toBeNull();
      expect(detailPane.querySelector(".flash")).toBeNull();
      expect(detailPane.querySelector(".other-formats")).toBeNull();
      expect(resultDiv.hidden).toBe(false);
      expect(resultDiv.innerHTML).toContain("ai-helper-loader");
    });

    it("does not restore the removed details when the generation ends in an error", async () => {
      const { detailPane, resultDiv } = addDetailPaneWithPreviousReport();
      addMeta("error-message", "Generation failed");
      const link = addGenerateLink();

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      FakeEventSource.instances[0].onerror();

      expect(resultDiv.innerHTML).toContain("Generation failed");
      expect(detailPane.querySelector(".ai-helper-health-report-meta")).toBeNull();
      expect(detailPane.querySelector(".ai-helper-health-report-edit-form")).toBeNull();
      expect(detailPane.querySelector(".other-formats")).toBeNull();
      expect(resultDiv.hidden).toBe(false);
    });

    it("removes nothing in the project overview structure (no .ai-helper-health-report-body)", async () => {
      const { healthDiv } = addHealthContainer();
      const meta = document.createElement("div");
      meta.className = "ai-helper-health-report-meta";
      healthDiv.appendChild(meta);
      const contextual = document.createElement("div");
      contextual.className = "contextual";
      healthDiv.appendChild(contextual);
      const link = addGenerateLink();

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(healthDiv.querySelector(".ai-helper-health-report-meta")).toBe(meta);
      expect(healthDiv.querySelector(".contextual")).toBe(contextual);
    });

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
