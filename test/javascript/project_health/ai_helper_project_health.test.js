import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScriptAndFireDOMContentLoaded } from "../support/dom_content_loaded.js";
import { loadScript } from "../support/load_script.js";
import { createDashboardDetailPane } from "../support/dashboard_detail_pane.js";

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

  function sendStop(source) {
    source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });
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

  describe("dashboard detail pane generation (no .ai-helper-project-health)", () => {
    it("finalizes a finished generation without throwing and creates the hidden field inside .ai-helper-project-health-content", async () => {
      const { contentDiv, resultDiv } = createDashboardDetailPane(container);
      const link = addGenerateLink();

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];

      expect(() => {
        source.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: "# Health" } }] }) });
        sendStop(source);
      }).not.toThrow();

      const hiddenField = document.getElementById("ai-helper-health-report-content");
      expect(hiddenField).not.toBeNull();
      expect(hiddenField.parentElement).toBe(contentDiv);
      expect(hiddenField.value).toBe("# Health");
      expect(resultDiv.innerHTML).toContain("ai-helper-final-content");
    });

    it("keeps exactly one hidden field with the latest content after two consecutive generations", async () => {
      const { contentDiv } = createDashboardDetailPane(container);
      const link = addGenerateLink();

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const first = FakeEventSource.instances[0];
      first.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: "first report" } }] }) });
      sendStop(first);

      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const second = FakeEventSource.instances[1];
      second.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: "second report" } }] }) });
      sendStop(second);

      const hiddenFields = contentDiv.querySelectorAll("#ai-helper-health-report-content");
      expect(hiddenFields.length).toBe(1);
      expect(hiddenFields[0].value).toBe("second report");
    });

    it("only refreshes the history when the whole detail pane was replaced during streaming", async () => {
      const { detailPane, contentDiv, resultDiv } = createDashboardDetailPane(container);
      const link = addGenerateLink();
      window.updateHealthReportHistory = vi.fn();

      await load();
      vi.useFakeTimers();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];
      source.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: "new report" } }] }) });

      // AiHelperMasterDetail#renderReportDetail replaces the detail
      // container's innerHTML when another report is selected, detaching
      // the whole pane — the result area keeps its
      // .ai-helper-project-health-content ancestor inside the detached
      // subtree, so the structural guard alone cannot catch this.
      detailPane.remove();
      const currentPane = createDashboardDetailPane(container);
      const currentHiddenField = document.createElement("input");
      currentHiddenField.type = "hidden";
      currentHiddenField.id = "ai-helper-health-report-content";
      currentHiddenField.value = "selected report";
      currentPane.contentDiv.appendChild(currentHiddenField);

      expect(() => sendStop(source)).not.toThrow();

      expect(resultDiv.innerHTML).not.toContain("ai-helper-final-content");
      expect(contentDiv.querySelector("#ai-helper-health-report-content")).toBeNull();
      expect(document.querySelectorAll("#ai-helper-health-report-content").length).toBe(1);
      expect(currentHiddenField.value).toBe("selected report");
      expect(currentPane.resultDiv.innerHTML).not.toContain("new report");

      // The new report was saved on the server, so the history list must
      // still pick it up.
      vi.advanceTimersByTime(1000);
      expect(window.updateHealthReportHistory).toHaveBeenCalledTimes(1);
    });

    it("throws a distinct message when the result element is not an HTMLElement", async () => {
      await load();
      const parser = new window.AiHelperMarkdownParser();

      expect(() => window.finalizeStreamingContent({}, parser, "content")).toThrow(
        /result area must be an HTMLElement/,
      );
    });

    it("throws a distinct message when the result element has no .ai-helper-project-health-content ancestor", async () => {
      await load();
      const parser = new window.AiHelperMarkdownParser();

      expect(() => window.finalizeStreamingContent(document.createElement("div"), parser, "content")).toThrow(
        /result area must have a \.ai-helper-project-health-content ancestor/,
      );
    });
    it("validates the result area before replacing the report body", async () => {
      const { resultDiv } = createDashboardDetailPane(container);
      const link = addGenerateLink();

      await load();
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[0];

      // Detaching the result area from its content container is the
      // structural failure the guard exists for: the finalized body must
      // not replace the page (nor the detached node) before the guard runs,
      // or the pane would look finished while history, export links and the
      // timestamp were never updated.
      resultDiv.remove();
      expect(() => sendStop(source)).toThrow(/ai-helper-project-health-content/);
      // The click left the loader in the result area; a finalize that ran
      // before the guard would have replaced it with the finished body.
      expect(resultDiv.innerHTML).toContain("ai-helper-loader");
      expect(resultDiv.innerHTML).not.toContain("ai-helper-final-content");
    });
  });
});
