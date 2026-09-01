import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";

function createXhrMock() {
  const xhr = {
    open: vi.fn(),
    send: vi.fn(),
    setRequestHeader: vi.fn(),
    responseText: "",
    status: 200,
    statusText: "OK",
    onprogress: null,
    onload: null,
    onerror: null,
    responseType: "text",
  };
  vi.stubGlobal("XMLHttpRequest", function () {
    return xhr;
  });
  return xhr;
}

describe("AiHelper streaming", () => {
  let helper;
  let xhr;

  beforeEach(async () => {
    await loadScript("assets/javascripts/chat/ai_helper");
    await loadScript("assets/javascripts/chat/ai_helper_streaming");
    xhr = createXhrMock();

    const meta = document.createElement("meta");
    meta.name = "csrf-token";
    meta.content = "test-csrf-token";
    document.head.appendChild(meta);

    helper = window.ai_helper;
  });

  afterEach(() => {
    const meta = document.querySelector('meta[name="csrf-token"]');
    if (meta) {meta.remove();}
    vi.unstubAllGlobals();
  });

  describe("handleSSEStream", () => {
    it("parses SSE data chunks and calls onContentCallback", () => {
      const chunks = [];
      helper.handleSSEStream(
        xhr,
        (content) => chunks.push(content),
        null,
        null
      );

      xhr.responseText = 'data: {"choices":[{"delta":{"content":"Hello"}}]}\n';
      xhr.onprogress();

      expect(chunks).toEqual(["Hello"]);
    });

    it("accumulates content across multiple chunks", () => {
      const fullResponses = [];
      helper.handleSSEStream(
        xhr,
        (_content, fullResponse) => fullResponses.push(fullResponse),
        null,
        null
      );

      xhr.responseText = 'data: {"choices":[{"delta":{"content":"Hello"}}]}' + '\n\n';
      xhr.onprogress();
      xhr.responseText += 'data: {"choices":[{"delta":{"content":" World"}}]}' + '\n\n';
      xhr.onprogress();

      expect(fullResponses).toEqual(["Hello", "Hello World"]);
    });

    it("calls onCompleteCallback on finish_reason stop", () => {
      let completed = false;
      helper.handleSSEStream(
        xhr,
        null,
        () => { completed = true; },
        null
      );

      xhr.responseText = 'data: {"choices":[{"delta":{"content":"Hi"},"finish_reason":"stop"}]}' + '\n\n';
      xhr.onprogress();

      expect(completed).toBe(true);
    });

    it("handles interactive_options event type", () => {
      let options = null;
      helper.handleSSEStream(
        xhr,
        null,
        null,
        (choices) => { options = choices; }
      );

      xhr.responseText = 'event: interactive_options\ndata: {"choices":[{"label":"A","value":"a"}]}\n\n';
      xhr.onprogress();

      expect(options).toEqual([{ label: "A", value: "a" }]);
    });

    it("handles malformed JSON gracefully", () => {
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
      const chunks = [];
      helper.handleSSEStream(
        xhr,
        (c) => chunks.push(c),
        null,
        null
      );

      xhr.responseText = 'data: {invalid json}\n';
      xhr.onprogress();

      expect(chunks).toEqual([]);
      expect(consoleError).toHaveBeenCalled();
      consoleError.mockRestore();
    });

    it("handles empty line resetting pending event type", () => {
      let options = null;
      helper.handleSSEStream(
        xhr,
        null,
        null,
        (choices) => { options = choices; }
      );

      xhr.responseText = 'event: interactive_options\n\n';
      xhr.onprogress();

      expect(options).toBeNull();
    });
  });

  describe("generateSummaryStream", () => {
    it("creates streaming content area and sends POST request", () => {
      const summaryArea = document.createElement("div");
      summaryArea.id = "ai-helper-summary-area";
      document.body.appendChild(summaryArea);

      helper.generateSummaryStream("/summary/url", "Error text");

      expect(xhr.open).toHaveBeenCalledWith("POST", "/summary/url", true);
      expect(xhr.setRequestHeader).toHaveBeenCalledWith(
        "Content-Type", "application/json"
      );

      summaryArea.remove();
    });

    it("sends CSRF token in header", () => {
      const summaryArea = document.createElement("div");
      summaryArea.id = "ai-helper-summary-area";
      document.body.appendChild(summaryArea);

      helper.generateSummaryStream("/summary/url", "Error");

      expect(xhr.setRequestHeader).toHaveBeenCalledWith(
        "X-CSRF-Token", "test-csrf-token"
      );

      summaryArea.remove();
    });
  });

  describe("generateReplyStream", () => {
    it("creates streaming content area and sends POST with instructions", () => {
      const replyArea = document.createElement("div");
      replyArea.id = "ai-helper-generate_reply-area";
      replyArea.style.display = "none";
      document.body.appendChild(replyArea);

      helper.generateReplyStream(
        "/reply/url",
        "Fix the bug",
        "Error text",
        "Apply",
        "Copy"
      );

      expect(xhr.open).toHaveBeenCalledWith("POST", "/reply/url", true);
      const sentData = JSON.parse(xhr.send.mock.calls[0][0]);
      expect(sentData.instructions).toBe("Fix the bug");

      replyArea.remove();
    });
  });

  describe("generateWikiSummaryStream", () => {
    it("creates streaming content and sends POST request", () => {
      const wikiSummaryArea = document.createElement("div");
      wikiSummaryArea.id = "ai-helper-wiki-summary-area";
      document.body.appendChild(wikiSummaryArea);

      helper.generateWikiSummaryStream("/wiki/summary/url", "Wiki Error");

      expect(xhr.open).toHaveBeenCalledWith("POST", "/wiki/summary/url", true);

      wikiSummaryArea.remove();
    });
  });

  describe("static parseSSELines", () => {
    function contentLine(text) {
      return 'data: {"choices":[{"delta":{"content":"' + text + '"}}]}'
    }
    function stopLine(text) {
      return 'data: {"choices":[{"delta":{"content":"' + text + '"},"finish_reason":"stop"}]}'
    }

    it("parses a content data line", () => {
      const result = window.AiHelper.parseSSELines(
        [contentLine("Hello")],
        null, "",
        () => {}, null, null
      );
      expect(result.fullResponse).toBe("Hello");
      expect(result.eventType).toBeNull();
    });

    it("returns pending event type for event lines", () => {
      const result = window.AiHelper.parseSSELines(
        ["event: interactive_options"],
        null, "",
        null, null, null
      );
      expect(result.eventType).toBe("interactive_options");
    });

    it("handles interactive_options event", () => {
      let choices = null;
      const result = window.AiHelper.parseSSELines(
        ["event: interactive_options", 'data: {"choices":[{"label":"A"}]}'],
        null, "",
        null, null, (c) => { choices = c; }
      );
      expect(choices).toEqual([{ label: "A" }]);
      expect(result.eventType).toBeNull();
    });

    it("accumulates content across multiple data lines", () => {
      const chunks = [];
      window.AiHelper.parseSSELines(
        [contentLine("Hello"), contentLine(" World")],
        null, "",
        (_c, full) => chunks.push(full), null, null
      );
      expect(chunks).toEqual(["Hello", "Hello World"]);
    });

    it("calls onComplete on finish_reason stop", () => {
      let completed = false;
      window.AiHelper.parseSSELines(
        [stopLine("Hi")],
        null, "",
        null, () => { completed = true; }, null
      );
      expect(completed).toBe(true);
    });

    it("handles malformed JSON gracefully", () => {
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
      const result = window.AiHelper.parseSSELines(
        ["data: {invalid}"],
        null, "",
        () => {}, null, null
      );
      expect(result.fullResponse).toBe("");
      expect(consoleError).toHaveBeenCalled();
      consoleError.mockRestore();
    });

    it("resets pending event type on empty line", () => {
      const result = window.AiHelper.parseSSELines(
        ["event: interactive_options", ""],
        null, "",
        null, null, null
      );
      expect(result.eventType).toBeNull();
    });
  });

  describe("generateSummaryStream error handling", () => {
    it("shows error text on xhr.onerror", () => {
      const summaryArea = document.createElement("div");
      summaryArea.id = "ai-helper-summary-area";
      document.body.appendChild(summaryArea);

      helper.generateSummaryStream("/summary/url", "Summary error");

      xhr.onerror();

      const streaming = summaryArea.querySelector("#ai-helper-streaming-summary");
      expect(streaming.textContent).toBe("Summary error");
      expect(streaming.previousElementSibling.style.display).toBe("none");

      summaryArea.remove();
    });

    it("shows error text on non-200 onload", () => {
      const summaryArea = document.createElement("div");
      summaryArea.id = "ai-helper-summary-area";
      document.body.appendChild(summaryArea);

      helper.generateSummaryStream("/summary/url", "Summary error");

      xhr.status = 500;
      xhr.statusText = "Internal Server Error";
      xhr.onload();

      const streaming = summaryArea.querySelector("#ai-helper-streaming-summary");
      expect(streaming.textContent).toBe("Error: 500 Internal Server Error");

      summaryArea.remove();
    });

    it("hides loader on first content chunk", () => {
      const summaryArea = document.createElement("div");
      summaryArea.id = "ai-helper-summary-area";
      document.body.appendChild(summaryArea);

      helper.generateSummaryStream("/summary/url", "Err");

      xhr.responseText = 'data: {"choices":[{"delta":{"content":"Hi"}}]}\n';
      xhr.onprogress();

      const loader = summaryArea.querySelector(".ai-helper-loader");
      expect(loader.style.display).toBe("none");

      summaryArea.remove();
    });
  });

  describe("generateReplyStream error and complete handling", () => {
    it("shows error text on xhr.onerror", () => {
      const replyArea = document.createElement("div");
      replyArea.id = "ai-helper-generate_reply-area";
      document.body.appendChild(replyArea);

      helper.generateReplyStream("/reply/url", "Fix", "Err", "Apply", "Copy");

      xhr.onerror();

      const streaming = replyArea.querySelector("#ai-helper-streaming-reply");
      expect(streaming.textContent).toBe("Err");

      replyArea.remove();
    });

    it("shows error text on non-200 onload", () => {
      const replyArea = document.createElement("div");
      replyArea.id = "ai-helper-generate_reply-area";
      document.body.appendChild(replyArea);

      helper.generateReplyStream("/reply/url", "Fix", "Err", "Apply", "Copy");

      xhr.status = 502;
      xhr.statusText = "Bad Gateway";
      xhr.onload();

      const streaming = replyArea.querySelector("#ai-helper-streaming-reply");
      expect(streaming.textContent).toBe("Error: 502 Bad Gateway");

      replyArea.remove();
    });

    it("creates apply button that sets issue_notes on complete", () => {
      const replyArea = document.createElement("div");
      replyArea.id = "ai-helper-generate_reply-area";
      document.body.appendChild(replyArea);

      const issueNotes = document.createElement("textarea");
      issueNotes.id = "issue_notes";
      document.body.appendChild(issueNotes);

      helper.generateReplyStream("/reply/url", "Fix", "Err", "Apply", "Copy");

      xhr.responseText = 'data: {"choices":[{"delta":{"content":"Reply text"},"finish_reason":"stop"}]}\n';
      xhr.onprogress();

      const applyBtn = replyArea.querySelector("button");
      expect(applyBtn.textContent).toBe("Apply");
      applyBtn.click();
      expect(issueNotes.value).toBe("Reply text");

      replyArea.remove();
      issueNotes.remove();
    });

    it("creates copy link that writes to clipboard on complete", () => {
      const replyArea = document.createElement("div");
      replyArea.id = "ai-helper-generate_reply-area";
      document.body.appendChild(replyArea);

      const writeText = vi.fn();
      vi.stubGlobal("navigator", { clipboard: { writeText } });

      helper.generateReplyStream("/reply/url", "Fix", "Err", "Apply", "Copy");

      xhr.responseText = 'data: {"choices":[{"delta":{"content":"Reply text"},"finish_reason":"stop"}]}\n';
      xhr.onprogress();

      const copyLink = replyArea.querySelector("a");
      expect(copyLink.textContent).toBe("Copy");
      copyLink.click();
      expect(writeText).toHaveBeenCalledWith("Reply text");

      replyArea.remove();
      vi.unstubAllGlobals();
    });
  });

  describe("generateWikiSummaryStream error handling", () => {
    it("shows error text on xhr.onerror", () => {
      const summaryArea = document.createElement("div");
      summaryArea.id = "ai-helper-wiki-summary-area";
      document.body.appendChild(summaryArea);

      helper.generateWikiSummaryStream("/wiki/summary/url", "Wiki err");

      xhr.onerror();

      const streaming = summaryArea.querySelector("#ai-helper-streaming-wiki-summary");
      expect(streaming.textContent).toBe("Wiki err");

      summaryArea.remove();
    });

    it("shows error text on non-200 onload", () => {
      const summaryArea = document.createElement("div");
      summaryArea.id = "ai-helper-wiki-summary-area";
      document.body.appendChild(summaryArea);

      helper.generateWikiSummaryStream("/wiki/summary/url", "Wiki err");

      xhr.status = 403;
      xhr.statusText = "Forbidden";
      xhr.onload();

      const streaming = summaryArea.querySelector("#ai-helper-streaming-wiki-summary");
      expect(streaming.textContent).toBe("Error: 403 Forbidden");

      summaryArea.remove();
    });
  });
});
