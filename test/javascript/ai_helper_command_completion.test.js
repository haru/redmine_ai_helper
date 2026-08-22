import { afterEach, beforeEach, describe, expect, it } from "vitest";
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

  it("Shift+Enter does not interfere with command completion state", () => {
    const { input } = createTestDOM();
    const completion = createCompletionWithCommands(input, [{ name: "alpha", description: "Alpha" }]);
    input.value = "/";

    simulateKeyDown(input, "Enter", { shiftKey: true });

    expect(completion.commands.length).toBeGreaterThan(0);
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
});
