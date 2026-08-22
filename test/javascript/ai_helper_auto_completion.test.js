import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "./support/load_script.js";

// Ported from the pre-existing (never-run) test/javascript/ai_helper_auto_completion_test.js.
// Verifies the fix for GitHub issue #392, where in-flight completion requests
// were never aborted and piled up until the browser ran out of same-origin
// connections, freezing unrelated actions such as saving an issue.
//
// Behaviour contracts covered here (C-1 .. C-7) are defined in
// specs/045-fix-autocompletion-request-pileup/contracts/completion-request-flow.md

/**
 * Helper: Create a minimal DOM environment for a single textarea instance.
 * @param {string} contextType 'description' | 'note' | 'wiki'
 */
function createTextareaDOM(contextType = "description") {
  const checkboxIds = {
    description: "ai-helper-autocompletion-description-toggle",
    note: "ai-helper-autocompletion-notes-toggle",
    wiki: "ai-helper-autocompletion-wiki-toggle",
  };
  const containerIds = {
    description: "ai-helper-description-checkbox-container",
    note: "ai-helper-notes-checkbox-container",
    wiki: "ai-helper-wiki-checkbox-container",
  };

  const container = document.createElement("div");

  const textarea = document.createElement("textarea");
  textarea.id = `textarea-${contextType}`;
  container.appendChild(textarea);

  const checkboxContainer = document.createElement("div");
  checkboxContainer.id = containerIds[contextType];

  const checkbox = document.createElement("input");
  checkbox.type = "checkbox";
  checkbox.id = checkboxIds[contextType];
  checkboxContainer.appendChild(checkbox);
  container.appendChild(checkboxContainer);

  document.body.appendChild(container);

  return { container, textarea, checkbox };
}

/**
 * Helper: Build an initialized AiHelperAutoCompletion instance in enabled state.
 * localStorage defaults the toggle to OFF, so enable it explicitly.
 */
function createCompletion(textarea, options = {}) {
  const completion = new window.AiHelperAutoCompletion(textarea, {
    endpoint: "/projects/1/ai_helper/issue/1/suggest_completion",
    debounceDelay: 0,
    minLength: 1,
    ...options,
  });
  completion.init();
  completion.isEnabled = true;
  if (completion.checkbox) {
    completion.checkbox.checked = true;
  }
  return completion;
}

/**
 * Helper: Replace global fetch with a stub that records every call and lets
 * the test settle each call individually. Restored by vi.unstubAllGlobals()
 * in afterEach.
 */
function installFetchStub() {
  const calls = [];

  vi.stubGlobal("fetch", function (url, options) {
    const call = { url, options, resolve: null, reject: null };
    call.promise = new Promise((resolve, reject) => {
      call.resolve = (data) => resolve({ ok: true, status: 200, json: () => Promise.resolve(data) });
      call.reject = reject;
    });
    calls.push(call);
    return call.promise;
  });

  return { calls };
}

/**
 * Helper: Wrap global AbortController so that abort() calls can be counted.
 * Restored by vi.unstubAllGlobals() in afterEach.
 */
function installAbortControllerSpy() {
  const OriginalAbortController = globalThis.AbortController;
  const instances = [];

  vi.stubGlobal("AbortController", class SpyAbortController extends OriginalAbortController {
    constructor() {
      super();
      this.abortCallCount = 0;
      instances.push(this);
    }

    abort() {
      this.abortCallCount++;
      super.abort();
    }
  });

  return { instances };
}

/** Helper: Build a DOMException-like AbortError, matching what fetch rejects with. */
function buildAbortError() {
  const error = new Error("The user aborted a request.");
  error.name = "AbortError";
  return error;
}

/** Helper: Let queued promise callbacks run. */
function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

/** Helper: Wait for a fixed number of milliseconds. */
function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

describe("AiHelperAutoCompletion request lifecycle", () => {
  let container;
  let fetchStub;
  let abortSpy;

  beforeEach(async () => {
    await loadScript("assets/javascripts/ai_helper_auto_completion");
    fetchStub = installFetchStub();
    abortSpy = installAbortControllerSpy();
  });

  afterEach(() => {
    if (container) container.remove();
    container = undefined;
    vi.unstubAllGlobals();
  });

  describe("C-1: single in-flight request (FR-001, FR-002)", () => {
    it("a new request aborts the previous in-flight request", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      completion.callCompletionAPI("first text", 10, 1);
      const firstController = completion.abortController;

      expect(firstController).not.toBeNull();
      expect(fetchStub.calls[0].options.signal).toBe(firstController.signal);

      completion.callCompletionAPI("second text", 11, 2);

      expect(firstController.abortCallCount).toBe(1);
      expect(completion.abortController).not.toBe(firstController);
      expect(fetchStub.calls[1].options.signal).toBe(completion.abortController.signal);
      expect(abortSpy.instances).toHaveLength(2);
    });

    it("abortController is released after the response settles", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "first text";
      completion.callCompletionAPI("first text", 10, ++completion.currentRequestId);
      fetchStub.calls[0].resolve({ suggestion: "" });
      await flushPromises();

      expect(completion.abortController).toBeNull();
    });

    it("a stale settlement leaves the newer controller in flight", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "first text";
      dom.textarea.setSelectionRange(10, 10);
      completion.requestSuggestion();

      dom.textarea.value = "second text";
      dom.textarea.setSelectionRange(11, 11);
      completion.requestSuggestion();
      const secondController = completion.abortController;

      // The first request only now reports that it was aborted
      fetchStub.calls[0].reject(buildAbortError());
      await flushPromises();

      expect(completion.abortController).toBe(secondController);

      // Which is what keeps the next request aborting the one still in
      // flight -- the connection exhaustion of issue #392 comes straight
      // back otherwise
      dom.textarea.value = "third text";
      dom.textarea.setSelectionRange(10, 10);
      completion.requestSuggestion();

      expect(secondController.signal.aborted).toBe(true);
    });
  });

  describe("C-2: every teardown path aborts through clearSuggestion (FR-003)", () => {
    it("clearSuggestion aborts the in-flight request", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      completion.callCompletionAPI("some text", 9, 1);
      const controller = completion.abortController;

      completion.clearSuggestion();

      expect(controller.signal.aborted).toBe(true);
      expect(completion.abortController).toBeNull();
    });

    it("disabling the checkbox aborts the in-flight request", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      completion.callCompletionAPI("some text", 9, 1);
      const controller = completion.abortController;

      dom.checkbox.checked = false;
      dom.checkbox.dispatchEvent(new Event("change"));

      expect(controller.signal.aborted).toBe(true);
    });

    it("blur aborts the in-flight request", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      completion.callCompletionAPI("some text", 9, 1);
      const controller = completion.abortController;

      completion.onBlur();
      await wait(150);

      expect(controller.signal.aborted).toBe(true);
    });

    it("accepting a suggestion aborts the in-flight request", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "some text";
      completion.currentSuggestion = { text: " completed", cursorPosition: 9 };
      completion.callCompletionAPI("some text", 9, 1);
      const controller = completion.abortController;

      completion.acceptSuggestion();

      expect(controller.signal.aborted).toBe(true);
    });

    it("Esc aborts the in-flight request", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      completion.currentSuggestion = { text: " completed", cursorPosition: 9 };
      completion.callCompletionAPI("some text", 9, 1);
      const controller = completion.abortController;

      completion.onKeyDown({ key: "Escape", preventDefault: () => {} });

      expect(controller.signal.aborted).toBe(true);
    });

    it("destroy aborts the in-flight request (page navigation edge case)", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      completion.callCompletionAPI("some text", 9, 1);
      const controller = completion.abortController;

      completion.destroy();

      expect(controller.signal.aborted).toBe(true);
    });
  });

  describe("C-3: aborting is a normal outcome, never an error (FR-004)", () => {
    it("an AbortError rejection produces no console output and no error UI", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});

      completion.callCompletionAPI("some text", 9, ++completion.currentRequestId);
      fetchStub.calls[0].reject(buildAbortError());
      await flushPromises();

      expect(consoleError).not.toHaveBeenCalled();
      expect(completion.currentSuggestion).toBeNull();

      consoleError.mockRestore();
    });

    it("non-abort errors are still reported, as before", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});

      completion.callCompletionAPI("some text", 9, ++completion.currentRequestId);
      fetchStub.calls[0].reject(new Error("HTTP error! status: 500"));
      await flushPromises();

      expect(consoleError).toHaveBeenCalledTimes(1);

      consoleError.mockRestore();
    });
  });

  describe("C-4: late responses are discarded (FR-005)", () => {
    it("a response that arrives after the request id advanced is not displayed", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "some text";
      const staleRequestId = ++completion.currentRequestId;
      completion.callCompletionAPI("some text", 9, staleRequestId);

      // A newer request supersedes it (this is what abort races with)
      completion.cancelPendingRequest();

      fetchStub.calls[0].resolve({ suggestion: " late suggestion" });
      await flushPromises();

      expect(completion.currentSuggestion).toBeNull();
    });

    it("a response is discarded when the text changed since the request was sent", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "some text";
      const requestId = ++completion.currentRequestId;
      completion.callCompletionAPI("some text", 9, requestId);

      dom.textarea.value = "some text edited";

      fetchStub.calls[0].resolve({ suggestion: " late suggestion" });
      await flushPromises();

      expect(completion.currentSuggestion).toBeNull();
    });
  });

  describe("C-7: instances are independent", () => {
    it("aborting one textarea's request leaves the other's request untouched", () => {
      const description = createTextareaDOM("description");
      const notes = createTextareaDOM("note");

      const descriptionCompletion = createCompletion(description.textarea, { contextType: "description" });
      const notesCompletion = createCompletion(notes.textarea, { contextType: "note" });

      descriptionCompletion.callCompletionAPI("description text", 16, 1);
      notesCompletion.callCompletionAPI("notes text", 10, 1);

      const descriptionController = descriptionCompletion.abortController;
      const notesController = notesCompletion.abortController;

      expect(descriptionController).not.toBe(notesController);

      descriptionCompletion.clearSuggestion();

      expect(descriptionController.signal.aborted).toBe(true);
      expect(notesController.signal.aborted).toBe(false);
      expect(notesCompletion.abortController).toBe(notesController);

      description.container.remove();
      notes.container.remove();
    });
  });

  describe("C-5: no request when nothing changed (FR-011)", () => {
    it("a second request for identical text and cursor is not sent", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "unchanged text";
      dom.textarea.setSelectionRange(14, 14);

      completion.requestSuggestion();
      expect(fetchStub.calls).toHaveLength(1);

      completion.requestSuggestion();
      expect(fetchStub.calls).toHaveLength(1);
    });

    it("moving the cursor without editing text issues a request only once per position", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "unchanged text";
      dom.textarea.setSelectionRange(14, 14);
      completion.requestSuggestion();

      dom.textarea.setSelectionRange(4, 4);
      completion.requestSuggestion();
      expect(fetchStub.calls).toHaveLength(2);

      completion.requestSuggestion();
      expect(fetchStub.calls).toHaveLength(2);
    });

    it("the manual Ctrl+Space trigger does not bypass the unchanged check", () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "unchanged text";
      dom.textarea.setSelectionRange(14, 14);
      completion.requestSuggestion();

      dom.textarea.dispatchEvent(new KeyboardEvent("keydown", {
        code: "Space",
        ctrlKey: true,
        bubbles: true,
        cancelable: true,
      }));

      expect(fetchStub.calls).toHaveLength(1);
    });

    it("accepting a suggestion leads into exactly one follow-on request", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea, { debounceDelay: 5 });

      dom.textarea.value = "some text";
      dom.textarea.setSelectionRange(9, 9);
      completion.currentSuggestion = { text: " completed", cursorPosition: 9 };

      completion.acceptSuggestion();
      await wait(40);

      // Accepting inserted text, so the next completion has to follow. The
      // input, keyup and click events accepting sets off must collapse into
      // a single one.
      expect(fetchStub.calls).toHaveLength(1);
      const sentText = JSON.parse(fetchStub.calls[0].options.body).text;
      expect(sentText).toBe("some text completed");
    });

    it("a repeat is still suppressed once the request has actually been answered", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "unchanged text";
      dom.textarea.setSelectionRange(14, 14);

      completion.requestSuggestion();
      fetchStub.calls[0].resolve({ suggestion: " more" });
      await flushPromises();

      completion.requestSuggestion();

      expect(fetchStub.calls).toHaveLength(1);
    });

    it("dismissing an answered suggestion with Esc leaves it re-requestable", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "unchanged text";
      dom.textarea.setSelectionRange(14, 14);

      completion.requestSuggestion();
      fetchStub.calls[0].resolve({ suggestion: " more" });
      await flushPromises();

      // The user reads the suggestion and turns it down without editing anything
      completion.onKeyDown({ key: "Escape", preventDefault: () => {} });

      completion.requestSuggestion();

      expect(fetchStub.calls).toHaveLength(2);
    });

    it("losing focus on an answered suggestion leaves it re-requestable", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "unchanged text";
      dom.textarea.setSelectionRange(14, 14);

      completion.requestSuggestion();
      fetchStub.calls[0].resolve({ suggestion: " more" });
      await flushPromises();

      // onBlur defers its teardown by 100ms
      completion.onBlur();
      await wait(150);

      completion.requestSuggestion();

      expect(fetchStub.calls).toHaveLength(2);
    });

    it("clearing must not clear a snapshot that belongs to a newer request", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "first text";
      dom.textarea.setSelectionRange(10, 10);
      completion.requestSuggestion();
      fetchStub.calls[0].resolve({ suggestion: " more" });
      await flushPromises();

      // The user types on, so the snapshot now describes the newer state
      dom.textarea.value = "second text";
      dom.textarea.setSelectionRange(11, 11);
      completion.requestSuggestion();

      // Clearing while the cursor sits somewhere else must leave that snapshot be
      dom.textarea.value = "first text";
      dom.textarea.setSelectionRange(10, 10);
      completion.clearSuggestion();

      expect(completion.lastTextSnapshot).toBe("second text");
    });

    it("a response with nothing to show leaves the position re-requestable", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      // '' is what a completion timeout returns: the controller answers 200
      // with an empty suggestion by design (ADR-018), and '   ' is a model
      // that produced only whitespace. Neither puts anything on screen.
      for (const emptyAnswer of ["", "   "]) {
        dom.textarea.value = `unchanged text ${emptyAnswer.length}`;
        dom.textarea.setSelectionRange(16, 16);
        const before = fetchStub.calls.length;

        completion.requestSuggestion();
        fetchStub.calls[before].resolve({ suggestion: emptyAnswer });
        await flushPromises();

        expect(completion.currentSuggestion).toBeNull();

        completion.requestSuggestion();
        expect(fetchStub.calls).toHaveLength(before + 2);
      }
    });

    it("a displayed suggestion survives an event that changed nothing", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "unchanged text";
      dom.textarea.setSelectionRange(14, 14);
      completion.requestSuggestion();
      fetchStub.calls[0].resolve({ suggestion: " more" });
      await flushPromises();

      // Releasing Shift, or clicking where the caret already is, reaches
      // onTextChange with the very state the suggestion was computed for
      dom.textarea.dispatchEvent(new KeyboardEvent("keyup", { key: "Shift", bubbles: true }));
      dom.textarea.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      await wait(20);

      expect(completion.currentSuggestion).not.toBeNull();
      expect(fetchStub.calls).toHaveLength(1);
    });

    it("taking a displayed suggestion off screen frees its position again", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "unchanged text";
      dom.textarea.setSelectionRange(14, 14);
      completion.requestSuggestion();
      fetchStub.calls[0].resolve({ suggestion: " more" });
      await flushPromises();

      // clearSuggestion is reached directly here, without going through Esc or blur
      dom.checkbox.checked = false;
      dom.checkbox.dispatchEvent(new Event("change"));

      expect(completion.currentSuggestion).toBeNull();

      completion.isEnabled = true;
      completion.requestSuggestion();

      expect(fetchStub.calls).toHaveLength(2);
    });

    it("an aborted request leaves the position re-requestable", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "unchanged text";
      dom.textarea.setSelectionRange(14, 14);

      completion.requestSuggestion();
      // Losing focus (or Esc, or accepting) aborts through clearSuggestion
      completion.clearSuggestion();
      fetchStub.calls[0].reject(buildAbortError());
      await flushPromises();

      completion.requestSuggestion();

      expect(fetchStub.calls).toHaveLength(2);
    });

    it("a failed request leaves the position re-requestable", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});

      dom.textarea.value = "unchanged text";
      dom.textarea.setSelectionRange(14, 14);

      completion.requestSuggestion();
      fetchStub.calls[0].reject(new Error("HTTP error! status: 500"));
      await flushPromises();

      completion.requestSuggestion();

      expect(fetchStub.calls).toHaveLength(2);

      consoleError.mockRestore();
    });

    it("a late failure must not clear the snapshot a newer request already set", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      dom.textarea.value = "first text";
      dom.textarea.setSelectionRange(10, 10);
      completion.requestSuggestion();

      dom.textarea.value = "second text";
      dom.textarea.setSelectionRange(11, 11);
      completion.requestSuggestion();

      // The first request only now reports that it was aborted
      fetchStub.calls[0].reject(buildAbortError());
      await flushPromises();

      expect(completion.lastTextSnapshot).toBe("second text");

      completion.requestSuggestion();
      expect(fetchStub.calls).toHaveLength(2);
    });
  });

  describe("C-6: a scheduled completion is cancelled when it becomes ineligible (FR-012)", () => {
    it("disabling autocompletion cancels the already scheduled completion", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea, { debounceDelay: 30 });

      dom.textarea.value = "long enough text";
      dom.textarea.setSelectionRange(16, 16);
      completion.scheduleCompletion();

      // The application's own path: unticking the box never reschedules, so
      // the scheduled completion has to be dropped by the teardown itself
      dom.checkbox.checked = false;
      dom.checkbox.dispatchEvent(new Event("change"));

      await wait(80);

      expect(fetchStub.calls).toHaveLength(0);
    });

    it("falling below the minimum length cancels the already scheduled completion", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea, { debounceDelay: 30, minLength: 5 });

      dom.textarea.value = "long enough text";
      dom.textarea.setSelectionRange(16, 16);
      completion.scheduleCompletion();

      dom.textarea.value = "ab";
      dom.textarea.setSelectionRange(2, 2);
      completion.scheduleCompletion();

      await wait(80);

      expect(fetchStub.calls).toHaveLength(0);
    });

    it("losing focus cancels the already scheduled completion", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      // The debounce has to outlast onBlur's own 100ms delay, as it does in
      // the application (500ms for issues, 300ms for wiki pages)
      const completion = createCompletion(dom.textarea, { debounceDelay: 300 });

      dom.textarea.value = "long enough text";
      dom.textarea.setSelectionRange(16, 16);
      completion.scheduleCompletion();

      completion.onBlur();
      await wait(400);

      expect(fetchStub.calls).toHaveLength(0);
    });

    it("destroy() detaches the listeners it registered", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea);

      completion.destroy();

      dom.textarea.value = "typed after the instance was destroyed";
      dom.textarea.setSelectionRange(37, 37);
      dom.textarea.dispatchEvent(new Event("input", { bubbles: true }));
      await wait(20);

      expect(fetchStub.calls).toHaveLength(0);
    });

    it("an eligible schedule still fires", async () => {
      const dom = createTextareaDOM();
      container = dom.container;
      const completion = createCompletion(dom.textarea, { debounceDelay: 10 });

      dom.textarea.value = "long enough text";
      dom.textarea.setSelectionRange(16, 16);
      completion.scheduleCompletion();

      await wait(60);

      expect(fetchStub.calls).toHaveLength(1);
    });
  });
});
