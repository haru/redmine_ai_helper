import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScriptAndFireDOMContentLoaded } from "./support/dom_content_loaded.js";
import { loadScript } from "./support/load_script.js";

// Ported from the pre-existing (never-run) test/javascript/ai_helper_command_completion_test.js.
// Verifies the fix where Enter selects a suggestion instead of submitting
// the chat form.

describe("CommandCompletion", () => {
  let container;

  beforeEach(async () => {
    await loadScript("assets/javascripts/ai_helper_command_completion");
  });

  afterEach(() => {
    if (container) container.remove();
    container = undefined;
    vi.unstubAllGlobals();
  });

  function createTestDOM() {
    container = document.createElement("div");

    const form = document.createElement("form");
    form.id = "ai_helper_chat_form";

    const input = document.createElement("textarea");
    input.id = "ai-helper-message-input";

    form.appendChild(input);
    container.appendChild(form);
    document.body.appendChild(container);

    return { input };
  }

  function createCompletionWithCommands(input, commands) {
    const completion = new window.CommandCompletion(input);
    completion.commands = commands;
    completion.showSuggestions();
    return completion;
  }

  function simulateKeyDown(element, key, options = {}) {
    const event = new KeyboardEvent("keydown", {
      key,
      bubbles: true,
      cancelable: true,
      ...options,
    });
    element.dispatchEvent(event);
    return event;
  }

  it("Enter after `/` selects the first command without submitting", () => {
    const { input } = createTestDOM();
    const completion = createCompletionWithCommands(input, [
      { name: "alpha", description: "Alpha command" },
      { name: "beta", description: "Beta command" },
    ]);
    input.value = "/";

    let formSubmitted = false;
    input.closest("form").addEventListener("submit", () => { formSubmitted = true; });

    simulateKeyDown(input, "Enter");

    expect(input.value).toBe("/alpha");
    expect(formSubmitted).toBe(false);
    expect(completion.isSuggestionsVisible()).toBe(false);
  });

  it("Enter with a single matching candidate selects it without submitting", () => {
    const { input } = createTestDOM();
    createCompletionWithCommands(input, [{ name: "abc_command", description: "ABC command" }]);
    input.value = "/abc";

    let formSubmitted = false;
    input.closest("form").addEventListener("submit", () => { formSubmitted = true; });

    simulateKeyDown(input, "Enter");

    expect(input.value).toBe("/abc_command");
    expect(formSubmitted).toBe(false);
  });

  it("arrow-key selection followed by Enter selects the chosen item", () => {
    const { input } = createTestDOM();
    createCompletionWithCommands(input, [
      { name: "alpha", description: "Alpha" },
      { name: "beta", description: "Beta" },
      { name: "gamma", description: "Gamma" },
    ]);
    input.value = "/";

    simulateKeyDown(input, "ArrowDown");
    simulateKeyDown(input, "ArrowDown");
    simulateKeyDown(input, "Enter");

    expect(input.value).toBe("/beta");
  });

  it("Enter does not intercept when suggestions are hidden (post-selection state)", () => {
    const { input } = createTestDOM();
    const completion = new window.CommandCompletion(input);
    input.value = "/alpha";

    expect(completion.isSuggestionsVisible()).toBe(false);

    // ai_helper.js's own keydown handler is responsible for submitting in
    // this state; CommandCompletion must not prevent default.
    const event = simulateKeyDown(input, "Enter");
    expect(event.defaultPrevented).toBe(false);
  });

  it("has no visible suggestions when the command list is empty", () => {
    const { input } = createTestDOM();
    const completion = new window.CommandCompletion(input);
    completion.commands = [];
    input.value = "/nonexistent";

    expect(completion.isSuggestionsVisible()).toBe(false);
  });

  it("does not show suggestions for normal text without a leading `/`", () => {
    const { input } = createTestDOM();
    const completion = new window.CommandCompletion(input);
    input.value = "Hello world";

    expect(completion.isSuggestionsVisible()).toBe(false);
  });

  it("Shift+Enter selects the suggestion just like plain Enter", () => {
    // CommandCompletion's own handleKeyDown does not special-case shiftKey --
    // it is ai_helper.js's keydown handler that checks shiftKey first and
    // returns early to allow a newline, before this class ever sees the
    // event. In isolation, Shift+Enter behaves exactly like Enter here.
    const { input } = createTestDOM();
    const completion = createCompletionWithCommands(input, [{ name: "alpha", description: "Alpha" }]);
    input.value = "/";

    const event = simulateKeyDown(input, "Enter", { shiftKey: true });

    expect(event.defaultPrevented).toBe(true);
    expect(input.value).toBe("/alpha");
    expect(completion.isSuggestionsVisible()).toBe(false);
  });

  it("Escape closes suggestions without changing the input text", () => {
    const { input } = createTestDOM();
    const completion = createCompletionWithCommands(input, [{ name: "alpha", description: "Alpha" }]);
    input.value = "/a";

    expect(completion.isSuggestionsVisible()).toBe(true);

    simulateKeyDown(input, "Escape");

    expect(completion.isSuggestionsVisible()).toBe(false);
    expect(input.value).toBe("/a");
  });

  it("clicking a suggestion selects the command without submitting", () => {
    const { input } = createTestDOM();
    const completion = createCompletionWithCommands(input, [
      { name: "alpha", description: "Alpha" },
      { name: "beta", description: "Beta" },
    ]);
    input.value = "/";

    let formSubmitted = false;
    input.closest("form").addEventListener("submit", () => { formSubmitted = true; });

    const items = completion.suggestionBox.querySelectorAll(".suggestion-item");
    items[1].click();

    expect(input.value).toBe("/beta");
    expect(formSubmitted).toBe(false);
    expect(completion.isSuggestionsVisible()).toBe(false);
  });

  it("stores a reference to itself on the input element", () => {
    const { input } = createTestDOM();
    const completion = new window.CommandCompletion(input);

    expect(input._commandCompletion).toBe(completion);
  });

  it("isSuggestionsVisible reflects visibility and command list state", () => {
    const { input } = createTestDOM();
    const completion = new window.CommandCompletion(input);

    expect(completion.isSuggestionsVisible()).toBe(false);

    completion.commands = [{ name: "test", description: "Test" }];
    completion.showSuggestions();
    expect(completion.isSuggestionsVisible()).toBe(true);

    completion.hideSuggestions();
    expect(completion.isSuggestionsVisible()).toBe(false);

    completion.commands = [];
    completion.suggestionBox.style.display = "block";
    expect(completion.isSuggestionsVisible()).toBe(false);
  });

  it("acceptSuggestion with no arrow-key selection picks the first item", () => {
    const { input } = createTestDOM();
    const completion = createCompletionWithCommands(input, [
      { name: "first", description: "First" },
      { name: "second", description: "Second" },
    ]);
    input.value = "/";

    expect(completion.selectedIndex).toBe(-1);

    const result = completion.acceptSuggestion();

    expect(result).toBe(true);
    expect(input.value).toBe("/first");
  });

  it("acceptSuggestion returns false when suggestions are not visible", () => {
    const { input } = createTestDOM();
    const completion = new window.CommandCompletion(input);

    expect(completion.acceptSuggestion()).toBe(false);
  });

  it("ArrowUp moves the selection to the previous item", () => {
    const { input } = createTestDOM();
    createCompletionWithCommands(input, [
      { name: "alpha", description: "Alpha" },
      { name: "beta", description: "Beta" },
      { name: "gamma", description: "Gamma" },
    ]);
    input.value = "/";

    simulateKeyDown(input, "ArrowDown");
    simulateKeyDown(input, "ArrowDown");
    simulateKeyDown(input, "ArrowDown");
    simulateKeyDown(input, "ArrowUp");
    simulateKeyDown(input, "Enter");

    expect(input.value).toBe("/beta");
  });

  it("ArrowUp does not move past the first item", () => {
    const { input } = createTestDOM();
    createCompletionWithCommands(input, [
      { name: "alpha", description: "Alpha" },
      { name: "beta", description: "Beta" },
    ]);
    input.value = "/";

    simulateKeyDown(input, "ArrowUp");
    simulateKeyDown(input, "Enter");

    expect(input.value).toBe("/alpha");
  });

  describe("handleInput", () => {
    it("fetches commands when the input starts with the command prefix", () => {
      const { input } = createTestDOM();
      const fetchMock = vi.fn(() => new Promise(() => {}));
      vi.stubGlobal("fetch", fetchMock);
      new window.CommandCompletion(input, "/ai_helper/commands");

      input.value = "/al";
      input.dispatchEvent(new Event("input", { bubbles: true }));

      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(fetchMock.mock.calls[0][0]).toContain("prefix=al");
    });

    it("hides suggestions and does not fetch when the input has no leading `/`", () => {
      const { input } = createTestDOM();
      const fetchMock = vi.fn();
      vi.stubGlobal("fetch", fetchMock);
      const completion = createCompletionWithCommands(input, [{ name: "alpha", description: "Alpha" }]);

      input.value = "hello";
      input.dispatchEvent(new Event("input", { bubbles: true }));

      expect(fetchMock).not.toHaveBeenCalled();
      expect(completion.isSuggestionsVisible()).toBe(false);
    });
  });

  describe("fetchCommands", () => {
    it("does nothing when no commandsUrl was provided", async () => {
      const { input } = createTestDOM();
      const fetchMock = vi.fn();
      vi.stubGlobal("fetch", fetchMock);
      const completion = new window.CommandCompletion(input);

      await completion.fetchCommands("a");

      expect(fetchMock).not.toHaveBeenCalled();
    });

    it("populates commands and shows suggestions on a successful response", async () => {
      const { input } = createTestDOM();
      vi.stubGlobal(
        "fetch",
        vi.fn(async () => ({
          json: async () => ({ commands: [{ name: "alpha", description: "Alpha" }] }),
        })),
      );
      const completion = new window.CommandCompletion(input, "/ai_helper/commands");

      await completion.fetchCommands("al");

      expect(completion.commands).toEqual([{ name: "alpha", description: "Alpha" }]);
      expect(completion.isSuggestionsVisible()).toBe(true);
    });

    it("defaults to an empty command list when the response has none", async () => {
      const { input } = createTestDOM();
      vi.stubGlobal("fetch", vi.fn(async () => ({ json: async () => ({}) })));
      const completion = new window.CommandCompletion(input, "/ai_helper/commands");

      await completion.fetchCommands("z");

      expect(completion.commands).toEqual([]);
      expect(completion.isSuggestionsVisible()).toBe(false);
    });

    it("hides suggestions and logs an error when the request fails", async () => {
      const { input } = createTestDOM();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
      vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("network down"); }));
      const completion = new window.CommandCompletion(input, "/ai_helper/commands");
      completion.commands = [{ name: "alpha", description: "Alpha" }];
      completion.showSuggestions();

      await completion.fetchCommands("a");

      expect(completion.isSuggestionsVisible()).toBe(false);
      expect(errorSpy).toHaveBeenCalled();
      errorSpy.mockRestore();
    });
  });

  describe("handleDocumentClick", () => {
    it("hides suggestions when clicking outside the input and suggestion box", () => {
      const { input } = createTestDOM();
      const completion = createCompletionWithCommands(input, [{ name: "alpha", description: "Alpha" }]);

      document.body.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(completion.isSuggestionsVisible()).toBe(false);
    });

    it("keeps suggestions open when clicking the input itself", () => {
      const { input } = createTestDOM();
      const completion = createCompletionWithCommands(input, [{ name: "alpha", description: "Alpha" }]);

      input.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(completion.isSuggestionsVisible()).toBe(true);
    });

    it("keeps suggestions open when clicking inside the suggestion box", () => {
      const { input } = createTestDOM();
      const completion = createCompletionWithCommands(input, [{ name: "alpha", description: "Alpha" }]);

      completion.suggestionBox.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(completion.isSuggestionsVisible()).toBe(true);
    });
  });

  describe("auto-init on DOMContentLoaded", () => {
    let cleanup;

    afterEach(() => {
      cleanup?.removeRegisteredListeners();
      cleanup = undefined;
    });

    it("initializes CommandCompletion on the chat input and marks it initialized", async () => {
      const { input } = createTestDOM();
      input.dataset.commandsUrl = "/ai_helper/commands";

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_command_completion");

      expect(input._commandCompletion).toBeInstanceOf(window.CommandCompletion);
      expect(input.dataset.commandCompletionInitialized).toBe("true");
    });

    it("does not initialize twice when already marked as initialized", async () => {
      const { input } = createTestDOM();
      input.dataset.commandCompletionInitialized = "true";

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_command_completion");

      expect(input._commandCompletion).toBeUndefined();
    });

    it("does nothing when the chat input is absent", async () => {
      await expect(
        (async () => {
          cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_command_completion");
        })(),
      ).resolves.toBeUndefined();
    });
  });
});
