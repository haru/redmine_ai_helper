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
    this.listeners = {};
    FakeEventSource.instances.push(this);
  }

  addEventListener(name, listener) {
    this.listeners[name] = this.listeners[name] || [];
    this.listeners[name].push(listener);
  }

  emit(name, event) {
    (this.listeners[name] || []).forEach((listener) => listener(event));
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
    await loadScript("assets/javascripts/project_health/ai_helper_chart_directive");
    await loadScript("assets/javascripts/project_health/ai_helper_project_health_swap");
  });

  afterEach(() => {
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    container.remove();
    document
      .querySelectorAll(
        'meta[name^="ai-helper-project-health"], meta[name="error-message"], meta[name="export-label"], ' +
          'meta[name="markdown-export-url"], meta[name="pdf-export-url"], meta[name="csrf-token"], ' +
          'meta[name="ai-helper-health-report-content-url"]',
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
    await loadScript("assets/javascripts/project_health/ai_helper_project_health_swap");
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

    it("still initializes the existing report and then fails loudly when the chart directive module is unavailable", async () => {
      delete window.AiHelperChartDirective;
      const { contentDiv } = addHealthContainer({ finalContent: true });
      addGenerateLink();

      await expect(load()).rejects.toThrow(/AiHelperChartDirective/);

      expect(window.aiHelperProjectHealthLoaded).toBe(true);
      expect(contentDiv.classList.contains("has-report")).toBe(true);
      expect(container.querySelector(".other-formats")).not.toBeNull();
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

  describe("chart directive stripping", () => {
    it("strips chart directives through stripForStreaming before parsing in appendStreamingChunk", async () => {
      const { resultDiv } = addHealthContainer();
      await load();

      const order = [];
      const stripSpy = vi.fn((markdown) => {
        order.push("strip");
        return markdown.replace(/^\{\{ai_helper_chart.*\n/m, "");
      });
      const parseSpy = vi.fn((markdown) => {
        order.push("parse");
        return "<p>" + markdown + "</p>";
      });
      vi.stubGlobal("AiHelperChartDirective", { stripForStreaming: stripSpy });

      window.appendStreamingChunk(
        resultDiv,
        { parse: parseSpy },
        "before\n{{ai_helper_chart(target: issues)}}\nafter",
      );

      expect(order).toEqual(["strip", "parse"]);
      expect(parseSpy).toHaveBeenCalledWith("before\nafter");
      expect(resultDiv.innerHTML).toContain("before\nafter");
      expect(resultDiv.innerHTML).not.toContain("ai_helper_chart");
    });

    it("strips chart directives through stripForStreaming before parsing in finalizeStreamingContent", async () => {
      const { resultDiv } = addHealthContainer();
      await load();

      const order = [];
      const stripSpy = vi.fn(() => {
        order.push("strip");
        return "stripped body";
      });
      const parseSpy = vi.fn((markdown) => {
        order.push("parse");
        return "<p>" + markdown + "</p>";
      });
      vi.stubGlobal("AiHelperChartDirective", { stripForStreaming: stripSpy });

      window.finalizeStreamingContent(resultDiv, { parse: parseSpy }, "raw {{ai_helper_chart(x)}}");

      expect(order).toEqual(["strip", "parse"]);
      expect(parseSpy).toHaveBeenCalledWith("stripped body");
      expect(resultDiv.innerHTML).toContain("ai-helper-final-content");
      expect(resultDiv.innerHTML).toContain("stripped body");
      expect(resultDiv.innerHTML).not.toContain("ai_helper_chart");
    });
  });

  describe("streaming display end to end (real directive module and parser)", () => {
    it("never shows a directive or its partial prefix while chunks arrive, and keeps the text around it", async () => {
      const { resultDiv } = addHealthContainer();
      const link = addGenerateLink();
      const frames = [];
      vi.stubGlobal("requestAnimationFrame", (callback) => frames.push(callback));
      vi.stubGlobal("cancelAnimationFrame", () => {});
      await load();

      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      const source = FakeEventSource.instances[FakeEventSource.instances.length - 1];
      const flush = () => frames.splice(0).forEach((callback) => callback());
      const send = (text) => source.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: text } }] }) });

      send("intro text\n{{ai_he");
      flush();
      expect(resultDiv.textContent).toContain("intro text");
      expect(resultDiv.innerHTML).not.toContain("{{ai_he");

      send("lper_chart(status, version=12)}}\nclosing text");
      flush();
      expect(resultDiv.textContent).toContain("intro text");
      expect(resultDiv.textContent).toContain("closing text");
      expect(resultDiv.innerHTML).not.toContain("ai_helper_chart");

      sendStop(source);
      expect(resultDiv.innerHTML).toContain("ai-helper-final-content");
      expect(resultDiv.innerHTML).not.toContain("ai_helper_chart");
      expect(resultDiv.textContent).toContain("closing text");
    });
  });

  describe("saved report content swap", () => {
    const SERVER_HTML =
      '<div class="ai-helper-health-report-content" data-pdf-url="/projects/ecookbook/ai_helper/health_reports/42.pdf" ' +
      'data-markdown-url="/projects/ecookbook/ai_helper/health_reports/42.md"><p>server rendered report</p></div>';

    function stubFetchWithServerHtml() {
      const fetchMock = vi.fn(async () => ({ ok: true, status: 200, text: async () => SERVER_HTML }));
      vi.stubGlobal("fetch", fetchMock);
      return fetchMock;
    }

    it("fetches the saved report content, swaps it in, and builds export links without ids", async () => {
      addMeta(
        "ai-helper-health-report-content-url",
        "/projects/ecookbook/ai_helper/health_reports/__REPORT_ID__/content",
      );
      addMeta("export-label", "Exporter");
      const { contentDiv, resultDiv } = addHealthContainer();
      const fetchMock = stubFetchWithServerHtml();

      await load();
      const returned = window.finalizeStreamingContent(
        resultDiv,
        new window.AiHelperMarkdownParser(),
        "client draft",
        42,
      );
      expect(returned).toBeInstanceOf(Promise);
      await returned;

      expect(fetchMock).toHaveBeenCalledWith(
        "/projects/ecookbook/ai_helper/health_reports/42/content",
        expect.objectContaining({ credentials: "same-origin" }),
      );
      expect(resultDiv.innerHTML).toBe(SERVER_HTML);

      const formats = contentDiv.querySelector(".other-formats");
      expect(formats).not.toBeNull();
      expect(formats.textContent).toContain("Exporter");
      expect(formats.querySelector("a.pdf").getAttribute("href")).toBe(
        "/projects/ecookbook/ai_helper/health_reports/42.pdf",
      );
      expect(formats.querySelector("a.text").getAttribute("href")).toBe(
        "/projects/ecookbook/ai_helper/health_reports/42.md",
      );
      // No ids: the POST-based export click handler keys on the -dynamic
      // ids, and these links must navigate instead.
      expect(formats.querySelector("a.pdf").id).toBe("");
      expect(formats.querySelector("a.text").id).toBe("");
    });

    it("does not route clicks on the swapped-in export links through the POST handlers", async () => {
      addMeta("ai-helper-health-report-content-url", "/__REPORT_ID__/content");
      const { contentDiv, resultDiv } = addHealthContainer();
      stubFetchWithServerHtml();

      await load();
      await window.finalizeStreamingContent(resultDiv, new window.AiHelperMarkdownParser(), "draft", 42);

      const pdfLink = contentDiv.querySelector(".other-formats a.pdf");
      window.handleProjectHealthExportClick({ target: pdfLink, preventDefault: vi.fn() });

      expect(document.body.querySelectorAll("form").length).toBe(0);
    });

    it("does not fetch the saved content and returns undefined when no report id is given", async () => {
      addMeta("ai-helper-health-report-content-url", "/__REPORT_ID__/content");
      const { resultDiv } = addHealthContainer();
      const fetchMock = vi.fn();
      vi.stubGlobal("fetch", fetchMock);

      await load();
      expect(
        window.finalizeStreamingContent(resultDiv, new window.AiHelperMarkdownParser(), "draft"),
      ).toBeUndefined();

      expect(fetchMock).not.toHaveBeenCalled();
      expect(resultDiv.innerHTML).toContain("ai-helper-final-content");
    });

    it("does not swap when the result area was detached while the content request was in flight", async () => {
      addMeta("ai-helper-health-report-content-url", "/__REPORT_ID__/content");
      const { resultDiv } = addHealthContainer();
      let resolveFetch;
      vi.stubGlobal(
        "fetch",
        vi.fn(() => new Promise((resolve) => { resolveFetch = resolve; })),
      );

      await load();
      const returned = window.finalizeStreamingContent(
        resultDiv,
        new window.AiHelperMarkdownParser(),
        "draft",
        42,
      );
      resultDiv.remove();
      resolveFetch({ ok: true, status: 200, text: async () => SERVER_HTML });

      await returned;

      expect(resultDiv.innerHTML).not.toContain("server rendered report");
      expect(resultDiv.innerHTML).toContain("ai-helper-final-content");
    });

    it("rejects when the saved content request responds with an error status", async () => {
      addMeta("ai-helper-health-report-content-url", "/__REPORT_ID__/content");
      const { resultDiv } = addHealthContainer();
      vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 403 })));

      await load();
      await expect(
        window.finalizeStreamingContent(resultDiv, new window.AiHelperMarkdownParser(), "draft", 42),
      ).rejects.toThrow(/403/);
    });

    it("rejects when the saved content request fails", async () => {
      addMeta("ai-helper-health-report-content-url", "/__REPORT_ID__/content");
      const { resultDiv } = addHealthContainer();
      vi.stubGlobal(
        "fetch",
        vi.fn(async () => {
          throw new TypeError("network down");
        }),
      );

      await load();
      await expect(
        window.finalizeStreamingContent(resultDiv, new window.AiHelperMarkdownParser(), "draft", 42),
      ).rejects.toThrow("network down");
    });

    it("throws before touching the DOM when the content-url meta tag is missing", async () => {
      const { resultDiv } = addHealthContainer();
      resultDiv.innerHTML = "<p>streaming</p>";
      await load();

      expect(() =>
        window.finalizeStreamingContent(resultDiv, new window.AiHelperMarkdownParser(), "draft", 42),
      ).toThrow(/content-url meta/);
      expect(resultDiv.innerHTML).toBe("<p>streaming</p>");
    });

    [0, -1, 1.5, "42"].forEach((badId) => {
      it(`throws before touching the DOM for the invalid saved report id ${JSON.stringify(badId)}`, async () => {
        addMeta("ai-helper-health-report-content-url", "/__REPORT_ID__/content");
        const { resultDiv } = addHealthContainer();
        resultDiv.innerHTML = "<p>streaming</p>";
        await load();

        expect(() =>
          window.finalizeStreamingContent(resultDiv, new window.AiHelperMarkdownParser(), "draft", badId),
        ).toThrow(/report id/);
        expect(resultDiv.innerHTML).toBe("<p>streaming</p>");
      });
    });

    it("refreshes the created-on metadata after swapping in the saved report", async () => {
      addMeta("ai-helper-health-report-content-url", "/__REPORT_ID__/content");
      addMeta("ai-helper-project-health-metadata-url", "/metadata");
      const { resultDiv } = addHealthContainer();
      const fetchMock = stubFetchWithServerHtml();

      await load();
      await window.finalizeStreamingContent(resultDiv, new window.AiHelperMarkdownParser(), "draft", 42);

      expect(fetchMock).toHaveBeenCalledWith("/metadata", expect.anything());
    });

    it("replaces the POST-based export links with the saved report's links in the project overview", async () => {
      addMeta("ai-helper-health-report-content-url", "/__REPORT_ID__/content");
      addMeta("pdf-export-url", "/post/pdf");
      addMeta("markdown-export-url", "/post/markdown");
      // The overview after a page load: an existing report body, so the
      // observer keeps adding the POST-based links during generation.
      const { healthDiv, resultDiv } = addHealthContainer({ finalContent: true });
      stubFetchWithServerHtml();

      await load();
      await window.finalizeStreamingContent(resultDiv, new window.AiHelperMarkdownParser(), "draft", 42);
      await new Promise((resolve) => setTimeout(resolve, 0));

      const rows = healthDiv.querySelectorAll(".other-formats");
      expect(rows.length).toBe(1);
      expect(rows[0].querySelector("a.pdf").getAttribute("href")).toBe(
        "/projects/ecookbook/ai_helper/health_reports/42.pdf",
      );
      expect(healthDiv.querySelector("#ai-helper-pdf-export-link-dynamic")).toBeNull();
    });

    it("rejects when the content response has no content root", async () => {
      addMeta("ai-helper-health-report-content-url", "/__REPORT_ID__/content");
      const { resultDiv } = addHealthContainer();
      vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, status: 200, text: async () => "<p>login</p>" })));

      await load();
      await expect(
        window.finalizeStreamingContent(resultDiv, new window.AiHelperMarkdownParser(), "draft", 42),
      ).rejects.toThrow(/ai-helper-health-report-content/);
    });

    it("rejects when the content root lacks an export URL", async () => {
      addMeta("ai-helper-health-report-content-url", "/__REPORT_ID__/content");
      const { resultDiv } = addHealthContainer();
      vi.stubGlobal("fetch", vi.fn(async () => ({
        ok: true,
        status: 200,
        text: async () => '<div class="ai-helper-health-report-content" data-pdf-url="/p.pdf"></div>',
      })));

      await load();
      await expect(
        window.finalizeStreamingContent(resultDiv, new window.AiHelperMarkdownParser(), "draft", 42),
      ).rejects.toThrow(/data-markdown-url/);
    });
  });
});
