import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "./support/load_script.js";

// --- T019: Characterization tests for wiki/_textarea_overlay.html.erb extraction ---

describe("initializeWikiCompletion (from wiki/_textarea_overlay.html.erb)", () => {
  let container;
  let autoCompletionMock;

  function createWikiDOM() {
    const parent = document.createElement("div");
    const textarea = document.createElement("textarea");
    textarea.id = "content_text";
    parent.appendChild(textarea);

    const checkboxContainer = document.createElement("div");
    checkboxContainer.id = "ai-helper-wiki-checkbox-container";
    parent.appendChild(checkboxContainer);

    document.body.appendChild(parent);
    return { parent, textarea, checkboxContainer };
  }

  beforeEach(() => {
    vi.useFakeTimers();
    autoCompletionMock = vi.fn();
    vi.stubGlobal("AiHelperAutoCompletion", autoCompletionMock);

    container = document.createElement("div");
    container.id = "ai-helper-wiki-textarea-overlay";
    container.dataset.config = JSON.stringify({
      endpoint: "/projects/test/ai_helper/suggest_wiki_completion",
      projectIdentifier: "test",
      userId: "1",
      isSectionEdit: false,
      debounceDelay: 300,
      minLength: 5,
      suggestionColor: "#888888",
      labels: {
        commonToggleLabel: "Toggle",
        loading: "Loading...",
        noSuggestions: "No suggestions",
        acceptSuggestion: "Accept",
        dismiss: "Dismiss",
        enabledTooltip: "Enabled",
        disabledTooltip: "Disabled",
      },
    });
    document.body.appendChild(container);

    window.aiHelperWikiCompletionInitialized = false;
  });

  afterEach(() => {
    vi.useRealTimers();
    document
      .querySelectorAll(
        "#ai-helper-wiki-textarea-overlay, #content_text, #ai-helper-wiki-checkbox-container"
      )
      .forEach((el) => el.remove());
    vi.unstubAllGlobals();
    delete window.aiHelperInstances;
    delete window.aiHelperWikiCompletionInitialized;
  });

  it("creates an AiHelperAutoCompletion instance for wiki textarea", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    const dom = createWikiDOM();
    await loadScript("assets/javascripts/ai_helper_wiki_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(autoCompletionMock).toHaveBeenCalledTimes(1);
    const callArgs = autoCompletionMock.mock.calls[0];
    expect(callArgs[0].id).toBe("content_text");
    expect(callArgs[1].contextType).toBe("wiki");
    expect(callArgs[1].userId).toBe("1");
    expect(callArgs[1].debounceDelay).toBe(300);
    expect(callArgs[1].minLength).toBe(5);
    expect(callArgs[1].suggestionColor).toBe("#888888");
    expect(callArgs[1].labels.commonToggleLabel).toBe("Toggle");

    dom.parent.remove();
  });

  it("does not reinitialize if aiHelperWikiCompletionInitialized is true", async () => {
    const dom = createWikiDOM();
    window.aiHelperWikiCompletionInitialized = true;
    await loadScript("assets/javascripts/ai_helper_wiki_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(autoCompletionMock).not.toHaveBeenCalled();
    dom.parent.remove();
  });

  it("stores wikiAutoCompletion on window.aiHelperInstances", async () => {
    const mockInstance = { init: vi.fn(), clearSuggestion: vi.fn() };
    autoCompletionMock.mockImplementation(function() { return mockInstance; });

    const dom = createWikiDOM();
    await loadScript("assets/javascripts/ai_helper_wiki_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(window.aiHelperInstances.wikiAutoCompletion).toBe(mockInstance);
    dom.parent.remove();
  });

  it("moves the checkbox container to below the textarea", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    const dom = createWikiDOM();
    await loadScript("assets/javascripts/ai_helper_wiki_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(dom.checkboxContainer.style.display).toBe("block");
    expect(dom.checkboxContainer.nextSibling).toBeNull();
    dom.parent.remove();
  });

  it("detects wiki page name from URL and adjusts endpoint", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    vi.stubGlobal("location", {
      pathname: "/projects/test/wiki/SomePage/edit",
    });
    const dom = createWikiDOM();
    await loadScript("assets/javascripts/ai_helper_wiki_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    const callArgs = autoCompletionMock.mock.calls[0];
    expect(callArgs[1].endpoint).toBe(
      "/projects/test/ai_helper/wiki/SomePage/suggest_completion"
    );
    dom.parent.remove();
  });

  it("does nothing when container element does not exist", async () => {
    container.remove();
    await loadScript("assets/javascripts/ai_helper_wiki_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(autoCompletionMock).not.toHaveBeenCalled();
  });

  it("does nothing when textarea does not exist", async () => {
    await loadScript("assets/javascripts/ai_helper_wiki_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(autoCompletionMock).not.toHaveBeenCalled();
  });

  it("does nothing when AiHelperAutoCompletion is undefined", async () => {
    vi.unstubAllGlobals();
    const dom = createWikiDOM();
    await loadScript("assets/javascripts/ai_helper_wiki_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(window.aiHelperWikiCompletionInitialized).toBe(true);
    dom.parent.remove();
  });
});

describe("initializeWikiTextareaTypoChecker (from wiki/_textarea_overlay.html.erb)", () => {
  let container;

  function createWikiTypoDOM() {
    const parent = document.createElement("div");
    parent.style.position = "relative";
    const textarea = document.createElement("textarea");
    textarea.id = "content_text";
    parent.appendChild(textarea);

    const button = document.createElement("button");
    button.id = "ai-helper-typo-check-wiki-btn";
    parent.appendChild(button);

    const controlPanel = document.createElement("div");
    controlPanel.id = "ai-helper-typo-control-panel-wiki";
    const applyAllBtn = document.createElement("button");
    applyAllBtn.className = "ai-helper-typo-apply-all-btn";
    controlPanel.appendChild(applyAllBtn);
    const closeBtn = document.createElement("button");
    closeBtn.className = "ai-helper-typo-close-btn";
    controlPanel.appendChild(closeBtn);
    parent.appendChild(controlPanel);

    const acceptTemplate = document.createElement("span");
    acceptTemplate.className = "ai-helper-typo-accept-btn-template";
    acceptTemplate.innerHTML = "✓";
    document.body.appendChild(acceptTemplate);
    const rejectTemplate = document.createElement("span");
    rejectTemplate.className = "ai-helper-typo-reject-btn-template";
    rejectTemplate.innerHTML = "✗";
    document.body.appendChild(rejectTemplate);

    const meta = document.createElement("meta");
    meta.name = "csrf-token";
    meta.content = "test-csrf-token";
    document.head.appendChild(meta);

    document.body.appendChild(parent);
    return { parent, textarea, button };
  }

  beforeEach(async () => {
    vi.useFakeTimers();
    await loadScript("assets/javascripts/ai_helper_typo_checker");

    container = document.createElement("div");
    container.id = "ai-helper-wiki-typo-overlay";
    container.dataset.config = JSON.stringify({
      endpoint: "/projects/test/ai_helper/check_typos",
      labels: {
        checkButton: "Check",
        checking: "Checking...",
        noSuggestions: "No typos",
        errorOccurred: "Error",
        correctionTooltip: "Correction",
        acceptSuggestion: "Accept",
        dismissSuggestion: "Reject",
        applyFailed: "Failed",
        suggestionsTitle: "Suggestions",
        acceptAll: "Accept All",
        dismissAll: "Dismiss All",
      },
    });
    document.body.appendChild(container);
  });

  afterEach(() => {
    vi.useRealTimers();
    document
      .querySelectorAll(
        "#ai-helper-wiki-typo-overlay, #ai-helper-wiki-textarea-overlay, #content_text, .ai-helper-typo-accept-btn-template, .ai-helper-typo-reject-btn-template, #ai-helper-typo-control-panel-wiki, meta[name=csrf-token]"
      )
      .forEach((el) => el.remove());
  });

  it("creates a typo checker and binds the check button click", async () => {
    const dom = createWikiTypoDOM();
    await loadScript("assets/javascripts/ai_helper_wiki_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(dom.textarea.classList.contains("ai-helper-textarea-positioned")).toBe(true);
    dom.parent.remove();
  });

  it("does nothing when textarea does not exist", async () => {
    await loadScript("assets/javascripts/ai_helper_wiki_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    // No error thrown
  });
});
