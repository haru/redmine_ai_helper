import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";

// ai_helper_stuff_todo.js wires up a "stuff to do" modal fed by an SSE
// (EventSource) stream. jsdom has no EventSource, so we stub a minimal fake
// that lets tests drive onmessage/onerror directly.

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

describe("ai_helper_stuff_todo", () => {
  let container;
  let frameCallbacks;

  function flushAnimationFrames() {
    const callbacks = Array.from(frameCallbacks.values());
    frameCallbacks.clear();
    callbacks.forEach((callback) => callback(0));
  }

  function sendChunk(source, text) {
    source.onmessage({ data: JSON.stringify({ choices: [{ delta: { content: text } }] }) });
  }

  beforeEach(async () => {
    container = document.createElement("div");
    document.body.appendChild(container);
    FakeEventSource.instances = [];
    vi.stubGlobal("EventSource", FakeEventSource);
    frameCallbacks = new Map();
    let nextFrameId = 1;
    vi.stubGlobal("requestAnimationFrame", (callback) => {
      const id = nextFrameId++;
      frameCallbacks.set(id, callback);
      return id;
    });
    vi.stubGlobal("cancelAnimationFrame", (id) => frameCallbacks.delete(id));
    delete window.aiHelperStuffTodoInitialized;
    delete window.AiHelperMarkdownParser;
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
  });

  afterEach(() => {
    container.remove();
    document.querySelectorAll('meta[name^="ai-helper-stuff-todo"]').forEach((meta) => meta.remove());
    vi.unstubAllGlobals();
  });

  function addMeta(name, content) {
    const meta = document.createElement("meta");
    meta.setAttribute("name", name);
    if (content !== undefined) {meta.setAttribute("content", content);}
    document.head.appendChild(meta);
    return meta;
  }

  function addMenuLink() {
    const li = document.createElement("li");
    const link = document.createElement("a");
    link.id = "ai-helper-stuff-todo-link";
    li.appendChild(link);
    container.appendChild(li);
    return link;
  }

  function addModalElements() {
    const overlay = document.createElement("div");
    overlay.id = "ai-helper-stuff-todo-overlay";
    const modal = document.createElement("div");
    modal.id = "ai-helper-stuff-todo-modal";
    const closeBtn = document.createElement("button");
    closeBtn.id = "ai-helper-stuff-todo-close";
    const body = document.createElement("div");
    body.id = "ai-helper-stuff-todo-body";
    container.append(overlay, modal, closeBtn, body);
    return { overlay, modal, closeBtn, body };
  }

  // The script attaches its top-level logic via a real
  // document.addEventListener('DOMContentLoaded', ...) call. Since `document`
  // is shared across every test in this file, dispatching a real
  // DOMContentLoaded event would also re-fire every listener left behind by
  // earlier tests (their closures still resolve elements by id, so they'd
  // reattach extra click handlers onto the *current* test's live elements).
  // Instead, intercept the registration and invoke only this test's handler
  // directly.
  async function load() {
    let handler;
    const addEventListenerSpy = vi
      .spyOn(document, "addEventListener")
      .mockImplementation((type, listener, options) => {
        if (type === "DOMContentLoaded") {
          handler = listener;
          return undefined;
        }
        return Document.prototype.addEventListener.call(document, type, listener, options);
      });

    await loadScript("assets/javascripts/stuff_todo/ai_helper_stuff_todo");
    addEventListenerSpy.mockRestore();

    handler();
    await new Promise((resolve) => setTimeout(resolve, 0));
  }

  it("hides the menu link and stops early when the URL meta tag is absent", async () => {
    const link = addMenuLink();

    await load();

    expect(link.closest("li").style.display).toBe("none");
  });

  it("does nothing when there is no menu link and no URL meta tag", async () => {
    await expect(load()).resolves.toBeUndefined();
  });

  it("shows the menu link but wires nothing up when the markdown parser is unavailable", async () => {
    delete window.AiHelperMarkdownParser;
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    addModalElements();

    await load();

    expect(link.style.display).toBe("inline-block");
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    expect(FakeEventSource.instances.length).toBe(0);
  });

  it("does nothing when required modal elements are missing from the page", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    // No modal elements added.

    await load();

    expect(link.style.display).toBe("inline-block");
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    expect(FakeEventSource.instances.length).toBe(0);
  });

  it("opens the modal, streams content, and finalizes on stop", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    const { overlay, modal, body } = addModalElements();

    await load();
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    expect(overlay.style.display).toBe("block");
    expect(modal.style.display).toBe("block");
    expect(FakeEventSource.instances.length).toBe(1);
    const source = FakeEventSource.instances[0];
    expect(source.url).toBe("/stuff_todo");

    sendChunk(source, "Hello ");
    flushAnimationFrames();
    expect(body.innerHTML).toContain("Hello");
    expect(body.innerHTML).toContain("ai-helper-cursor");

    sendChunk(source, "world");
    flushAnimationFrames();
    expect(body.innerHTML).toContain("Hello world");

    source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });
    expect(body.innerHTML).toContain("ai-helper-final-content");
    expect(body.innerHTML).toContain("Hello world");
    expect(source.closed).toBe(true);
  });

  it("coalesces chunks that arrive within one animation frame into a single render", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    const { body } = addModalElements();
    const parseSpy = vi.spyOn(window.AiHelperMarkdownParser.prototype, "parse");

    await load();
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    const source = FakeEventSource.instances[0];

    sendChunk(source, "one ");
    sendChunk(source, "two ");
    sendChunk(source, "three");

    expect(parseSpy).not.toHaveBeenCalled();
    expect(body.innerHTML).toContain("ai-helper-loader");
    expect(frameCallbacks.size).toBe(1);

    flushAnimationFrames();

    expect(parseSpy).toHaveBeenCalledTimes(1);
    expect(parseSpy).toHaveBeenCalledWith("one two three");
    expect(body.innerHTML).toContain("one two three");
    parseSpy.mockRestore();
  });

  it("cancels a pending streaming render when the stream finishes", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    const { body } = addModalElements();

    await load();
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    const source = FakeEventSource.instances[0];

    sendChunk(source, "final text");
    source.onmessage({ data: JSON.stringify({ choices: [{ finish_reason: "stop" }] }) });

    expect(frameCallbacks.size).toBe(0);
    expect(body.innerHTML).toContain("ai-helper-final-content");
    expect(body.innerHTML).toContain("final text");
    expect(body.innerHTML).not.toContain("ai-helper-cursor");
  });

  it("cancels a pending streaming render when the stream errors", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    const { body } = addModalElements();

    await load();
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    const source = FakeEventSource.instances[0];

    sendChunk(source, "partial");
    source.onerror();

    expect(frameCallbacks.size).toBe(0);
    expect(body.innerHTML).toContain("ai-helper-error");
  });

  it("drops a pending render once the modal is closed", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    const { body, closeBtn } = addModalElements();

    await load();
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    sendChunk(FakeEventSource.instances[0], "stale text");

    closeBtn.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    flushAnimationFrames();

    expect(body.innerHTML).not.toContain("stale text");
  });

  it("drops a pending render from a stream replaced by reopening the modal", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    const { body } = addModalElements();

    await load();
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    sendChunk(FakeEventSource.instances[0], "stale text");

    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    flushAnimationFrames();

    expect(body.innerHTML).toContain("ai-helper-loader");
    expect(body.innerHTML).not.toContain("stale text");
  });

  it("silently ignores malformed SSE payloads", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    const { body } = addModalElements();

    await load();
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    const source = FakeEventSource.instances[0];

    expect(() => source.onmessage({ data: "not json" })).not.toThrow();
    expect(body.innerHTML).toContain("ai-helper-loader");
  });

  it("shows the configured error message and closes the stream on error", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    addMeta("ai-helper-stuff-todo-error", "Something went wrong");
    const link = addMenuLink();
    const { body } = addModalElements();

    await load();
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    const source = FakeEventSource.instances[0];

    source.onerror();

    expect(body.innerHTML).toContain("Something went wrong");
    expect(source.closed).toBe(true);
  });

  it("falls back to a generic error message when no error meta tag is present", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    const { body } = addModalElements();

    await load();
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    const source = FakeEventSource.instances[0];

    source.onerror();

    expect(body.innerHTML).toContain("Error");
  });

  it("closes the modal and the event source via the close button", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    const { overlay, modal, closeBtn } = addModalElements();

    await load();
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    const source = FakeEventSource.instances[0];

    closeBtn.dispatchEvent(new MouseEvent("click", { bubbles: true }));

    expect(overlay.style.display).toBe("none");
    expect(modal.style.display).toBe("none");
    expect(source.closed).toBe(true);
  });

  it("closes the modal when the overlay is clicked", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    const { overlay, modal } = addModalElements();

    await load();
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    overlay.dispatchEvent(new MouseEvent("click", { bubbles: true }));

    expect(overlay.style.display).toBe("none");
    expect(modal.style.display).toBe("none");
  });

  it("closes the modal on Escape only while it is open", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    const { overlay, modal } = addModalElements();

    await load();

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    expect(modal.style.display).not.toBe("block");

    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    expect(modal.style.display).toBe("block");

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    expect(overlay.style.display).toBe("none");
    expect(modal.style.display).toBe("none");
  });

  it("closes a previous stream before starting a new one on reopen", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    addModalElements();

    await load();
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    const first = FakeEventSource.instances[0];

    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    expect(first.closed).toBe(true);
    expect(FakeEventSource.instances.length).toBe(2);
  });

  it("skips re-initialization on a second load when the guard flag is already set", async () => {
    addMeta("ai-helper-stuff-todo-url", "/stuff_todo");
    const link = addMenuLink();
    addModalElements();
    window.aiHelperStuffTodoInitialized = true;

    // vi.resetModules() only clears the module cache, not window state, so
    // re-importing with the guard flag already set must be a no-op: the
    // script never reaches document.addEventListener('DOMContentLoaded', ...).
    const addEventListenerSpy = vi.spyOn(document, "addEventListener");
    await loadScript("assets/javascripts/stuff_todo/ai_helper_stuff_todo");

    expect(addEventListenerSpy).not.toHaveBeenCalledWith("DOMContentLoaded", expect.any(Function));
    addEventListenerSpy.mockRestore();
    void link;
  });
});
