import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "./support/load_script.js";

// --- T020: Characterization tests for shared/_textarea_overlay.html.erb extraction ---

describe("initalizeIssueCompletion (from shared/_textarea_overlay.html.erb)", () => {
  let container;
  let autoCompletionMock;

  function createIssueDOM() {
    const form = document.createElement("div");

    const descTextarea = document.createElement("textarea");
    descTextarea.id = "issue_description";
    form.appendChild(descTextarea);

    const descContainer = document.createElement("div");
    descContainer.id = "ai-helper-description-checkbox-container";
    form.appendChild(descContainer);

    const notesTextarea = document.createElement("textarea");
    notesTextarea.id = "issue_notes";
    form.appendChild(notesTextarea);

    const notesContainer = document.createElement("div");
    notesContainer.id = "ai-helper-notes-checkbox-container";
    form.appendChild(notesContainer);

    document.body.appendChild(form);
    return { form, descTextarea, notesTextarea, descContainer, notesContainer };
  }

  function createConfig(overrides = {}) {
    return JSON.stringify({
      descriptionEndpoint: "/projects/1/ai_helper/issues/new/suggest_completion",
      userId: "1",
      isPersistedIssue: false,
      issueId: null,
      projectId: "1",
      debounceDelay: 500,
      minLength: 5,
      suggestionColor: "#888888",
      duplicateCheckEndpoint: "/projects/1/ai_helper/check_duplicates",
      notesEndpoint: "#",
      labels: {
        commonToggleLabel: "Toggle",
        loading: "Loading...",
        noSuggestions: "No suggestions",
        acceptSuggestion: "Accept",
        dismiss: "Dismiss",
        enabledTooltip: "Enabled",
        disabledTooltip: "Disabled",
        noteEnabledTooltip: "Note Enabled",
        noteDisabledTooltip: "Note Disabled",
      },
      duplicateCheckLabels: {
        emptyContent: "Please enter subject or description",
      },
      ...overrides,
    });
  }

  beforeEach(() => {
    vi.useFakeTimers();
    autoCompletionMock = vi.fn();
    vi.stubGlobal("AiHelperAutoCompletion", autoCompletionMock);

    const meta = document.createElement("meta");
    meta.name = "csrf-token";
    meta.content = "test-csrf-token";
    document.head.appendChild(meta);

    container = document.createElement("div");
    container.id = "ai-helper-issue-textarea-overlay";
    container.dataset.config = createConfig();
    document.body.appendChild(container);

    window.aiHelperAutoCompletionInitialized = false;
  });

  afterEach(() => {
    vi.useRealTimers();
    document
      .querySelectorAll(
        "#ai-helper-issue-textarea-overlay, #issue_description, #issue_notes, #ai-helper-description-checkbox-container, #ai-helper-notes-checkbox-container, #ai-helper-duplicate-check-container, #ai-helper-duplicate-check-btn, #ai-helper-duplicate-check-results, #ai-helper-duplicate-check-loading, #issue_subject, meta[name=csrf-token]"
      )
      .forEach((el) => el.remove());
    vi.unstubAllGlobals();
    delete window.aiHelperInstances;
    delete window.aiHelperAutoCompletionInitialized;
  });

  it("creates an AiHelperAutoCompletion for description textarea", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    const dom = createIssueDOM();
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(autoCompletionMock).toHaveBeenCalled();
    const callArgs = autoCompletionMock.mock.calls[0];
    expect(callArgs[0].id).toBe("issue_description");
    expect(callArgs[1].contextType).toBe("description");
    expect(callArgs[1].userId).toBe("1");
    expect(callArgs[1].debounceDelay).toBe(500);
    expect(callArgs[1].minLength).toBe(5);
    expect(callArgs[1].labels.commonToggleLabel).toBe("Toggle");

    dom.form.remove();
  });

  it("stores autoCompletion on window.aiHelperInstances", async () => {
    const mockInstance = { init: vi.fn(), clearSuggestion: vi.fn() };
    autoCompletionMock.mockImplementation(function() { return mockInstance; });
    const dom = createIssueDOM();
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(window.aiHelperInstances.autoCompletion).toBe(mockInstance);
    dom.form.remove();
  });

  it("moves the description checkbox container below the textarea", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    const dom = createIssueDOM();
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(dom.descContainer.style.display).toBe("block");
    dom.form.remove();
  });

  it("does not reinitialize if aiHelperAutoCompletionInitialized is true", async () => {
    window.aiHelperAutoCompletionInitialized = true;
    const dom = createIssueDOM();
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(autoCompletionMock).not.toHaveBeenCalled();
    dom.form.remove();
  });

  it("creates notes autocompletion when isPersistedIssue is true and notes textarea exists", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    container.dataset.config = createConfig({
      isPersistedIssue: true,
      notesEndpoint: "/projects/1/ai_helper/issues/5/suggest_completion",
      issueId: "5",
    });
    const dom = createIssueDOM();
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(autoCompletionMock).toHaveBeenCalledTimes(2);
    const notesCall = autoCompletionMock.mock.calls[1];
    expect(notesCall[0].id).toBe("issue_notes");
    expect(notesCall[1].contextType).toBe("note");
    expect(notesCall[1].issueId).toBe("5");
    expect(notesCall[1].labels.enabledTooltip).toBe("Note Enabled");

    dom.form.remove();
  });

  it("does not create notes autocompletion when isPersistedIssue is false", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    container.dataset.config = createConfig({ isPersistedIssue: false });
    const dom = createIssueDOM();
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(autoCompletionMock).toHaveBeenCalledTimes(1);
    dom.form.remove();
  });

  it("stores notesAutoCompletion on window.aiHelperInstances for persisted issues", async () => {
    const mockInstance = { init: vi.fn(), clearSuggestion: vi.fn() };
    autoCompletionMock.mockImplementation(function() { return mockInstance; });
    container.dataset.config = createConfig({
      isPersistedIssue: true,
      notesEndpoint: "/projects/1/ai_helper/issues/5/suggest_completion",
      issueId: "5",
    });
    const dom = createIssueDOM();
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(window.aiHelperInstances.notesAutoCompletion).toBe(mockInstance);
    dom.form.remove();
  });

  it("does nothing when container does not exist", async () => {
    container.remove();
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(autoCompletionMock).not.toHaveBeenCalled();
  });

  it("does nothing when description textarea does not exist and isPersistedIssue is false", async () => {
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(autoCompletionMock).not.toHaveBeenCalled();
  });
});

describe("initializeIssueTypoChecker (from shared/_textarea_overlay.html.erb)", () => {
  let container;

  function createIssueTypoDOM() {
    const form = document.createElement("div");
    form.style.position = "relative";

    const descTextarea = document.createElement("textarea");
    descTextarea.id = "issue_description";
    form.appendChild(descTextarea);

    const descBtn = document.createElement("button");
    descBtn.id = "ai-helper-typo-check-description-btn";
    form.appendChild(descBtn);

    const notesTextarea = document.createElement("textarea");
    notesTextarea.id = "issue_notes";
    form.appendChild(notesTextarea);

    const notesBtn = document.createElement("button");
    notesBtn.id = "ai-helper-typo-check-notes-btn";
    form.appendChild(notesBtn);

    const descPanel = document.createElement("div");
    descPanel.id = "ai-helper-typo-control-panel-description";
    const applyAllBtn = document.createElement("button");
    applyAllBtn.className = "ai-helper-typo-apply-all-btn";
    descPanel.appendChild(applyAllBtn);
    const closeBtn = document.createElement("button");
    closeBtn.className = "ai-helper-typo-close-btn";
    descPanel.appendChild(closeBtn);
    form.appendChild(descPanel);

    const notesPanel = document.createElement("div");
    notesPanel.id = "ai-helper-typo-control-panel-notes";
    const applyAllBtn2 = document.createElement("button");
    applyAllBtn2.className = "ai-helper-typo-apply-all-btn";
    notesPanel.appendChild(applyAllBtn2);
    const closeBtn2 = document.createElement("button");
    closeBtn2.className = "ai-helper-typo-close-btn";
    notesPanel.appendChild(closeBtn2);
    form.appendChild(notesPanel);

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

    document.body.appendChild(form);
    return { form, descTextarea, notesTextarea, descBtn, notesBtn };
  }

  beforeEach(async () => {
    vi.useFakeTimers();
    await loadScript("assets/javascripts/ai_helper_typo_checker");

    container = document.createElement("div");
    container.id = "ai-helper-issue-typo-overlay";
    container.dataset.config = JSON.stringify({
      endpoint: "/projects/1/ai_helper/check_typos",
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
        "#ai-helper-issue-typo-overlay, #ai-helper-issue-textarea-overlay, #issue_description, #issue_notes, .ai-helper-typo-accept-btn-template, .ai-helper-typo-reject-btn-template, #ai-helper-typo-control-panel-description, #ai-helper-typo-control-panel-notes, meta[name=csrf-token]"
      )
      .forEach((el) => el.remove());
  });

  it("creates typo checkers for both description and notes textareas", async () => {
    const dom = createIssueTypoDOM();
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(dom.descTextarea.classList.contains("ai-helper-textarea-positioned")).toBe(true);
    expect(dom.notesTextarea.classList.contains("ai-helper-textarea-positioned")).toBe(true);
    dom.form.remove();
  });

  it("does nothing when container does not exist", async () => {
    container.remove();
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    // No error thrown
  });
});

describe("initializeAssignmentSuggestion (from shared/_textarea_overlay.html.erb)", () => {
  let container;
  let assignmentMock;

  beforeEach(() => {
    vi.useFakeTimers();
    assignmentMock = vi.fn();
    vi.stubGlobal("AiHelperAssignmentSuggestion", assignmentMock);

    const select = document.createElement("select");
    select.id = "issue_assigned_to_id";
    document.body.appendChild(select);

    container = document.createElement("div");
    container.id = "ai-helper-issue-textarea-overlay";
    container.dataset.assignmentConfig = JSON.stringify({
      endpoint: "/projects/1/ai_helper/suggest_assignees",
      robotIconHtml: "<svg>icon</svg>",
      labels: {
        linkLabel: "Suggest",
        loading: "Loading...",
        close: "Close",
        noSuggestions: "No suggestions",
        error: "Error",
        emptyContent: "Enter content",
        historyTitle: "History",
        historyScore: "Score",
        historySimilarCount: "3",
        workloadTitle: "Workload",
        workloadOpenIssues: "5",
        workloadUnit: "issues",
        instructionTitle: "Instruction",
        instructionReason: "Reason",
      },
    });
    document.body.appendChild(container);
  });

  afterEach(() => {
    vi.useRealTimers();
    document
      .querySelectorAll(
        "#ai-helper-issue-textarea-overlay, #issue_assigned_to_id"
      )
      .forEach((el) => el.remove());
    vi.unstubAllGlobals();
  });

  it("creates an AiHelperAssignmentSuggestion when select and container exist", async () => {
    assignmentMock.mockImplementation(function() { this.init = vi.fn(); });
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(assignmentMock).toHaveBeenCalledTimes(1);
    const callArgs = assignmentMock.mock.calls[0][0];
    expect(callArgs.endpoint).toBe("/projects/1/ai_helper/suggest_assignees");
    expect(callArgs.labels.linkLabel).toBe("Suggest");
  });

  it("does nothing when AiHelperAssignmentSuggestion is undefined", async () => {
    vi.unstubAllGlobals();
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    // No error thrown
  });

  it("does nothing when assigned_to select does not exist", async () => {
    document.getElementById("issue_assigned_to_id").remove();
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    expect(assignmentMock).not.toHaveBeenCalled();
  });
});

describe("Duplicate check (from shared/_textarea_overlay.html.erb)", () => {
  let container;

  function createDuplicateCheckDOM() {
    const form = document.createElement("div");

    const descTextarea = document.createElement("textarea");
    descTextarea.id = "issue_description";
    form.appendChild(descTextarea);

    const descContainer = document.createElement("div");
    descContainer.id = "ai-helper-description-checkbox-container";
    form.appendChild(descContainer);

    const dupContainer = document.createElement("div");
    dupContainer.id = "ai-helper-duplicate-check-container";
    form.appendChild(dupContainer);

    const dupBtn = document.createElement("button");
    dupBtn.id = "ai-helper-duplicate-check-btn";
    dupContainer.appendChild(dupBtn);

    const dupResults = document.createElement("div");
    dupResults.id = "ai-helper-duplicate-check-results";
    dupContainer.appendChild(dupResults);

    const dupLoading = document.createElement("div");
    dupLoading.id = "ai-helper-duplicate-check-loading";
    dupContainer.appendChild(dupLoading);

    const subjectInput = document.createElement("input");
    subjectInput.id = "issue_subject";
    form.appendChild(subjectInput);

    const meta = document.createElement("meta");
    meta.name = "csrf-token";
    meta.content = "test-csrf-token";
    document.head.appendChild(meta);

    document.body.appendChild(form);
    return { form, descTextarea, dupBtn, dupResults, dupLoading, subjectInput };
  }

  beforeEach(() => {
    vi.useFakeTimers();
    const acMock = vi.fn();
    acMock.mockImplementation(function() { this.init = vi.fn(); });
    vi.stubGlobal("AiHelperAutoCompletion", acMock);

    container = document.createElement("div");
    container.id = "ai-helper-issue-textarea-overlay";
    container.dataset.config = JSON.stringify({
      descriptionEndpoint: "/test",
      userId: "1",
      isPersistedIssue: false,
      issueId: null,
      projectId: "1",
      debounceDelay: 500,
      minLength: 5,
      suggestionColor: "#888888",
      duplicateCheckEndpoint: "/projects/1/ai_helper/check_duplicates",
      notesEndpoint: "#",
      labels: {},
      duplicateCheckLabels: {
        emptyContent: "Please enter subject or description",
      },
    });
    document.body.appendChild(container);
    window.aiHelperAutoCompletionInitialized = false;
  });

  afterEach(() => {
    vi.useRealTimers();
    document
      .querySelectorAll(
        "#ai-helper-issue-textarea-overlay, #issue_description, #ai-helper-description-checkbox-container, #ai-helper-duplicate-check-container, #issue_subject, meta[name=csrf-token]"
      )
      .forEach((el) => el.remove());
    vi.unstubAllGlobals();
    delete window.aiHelperInstances;
    delete window.aiHelperAutoCompletionInitialized;
  });

  it("shows alert when subject and description are empty", async () => {
    const alertMock = vi.fn();
    vi.stubGlobal("alert", alertMock);
    const dom = createDuplicateCheckDOM();
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    dom.dupBtn.click();
    expect(alertMock).toHaveBeenCalledWith("Please enter subject or description");
    dom.form.remove();
  });

  it("shows loading and hides results on click", async () => {
    const dom = createDuplicateCheckDOM();
    dom.descTextarea.value = "some content";
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      text: () => Promise.resolve("<div>results</div>"),
    }));
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    dom.dupBtn.click();
    expect(dom.dupLoading.style.display).toBe("flex");
    expect(dom.dupResults.style.display).toBe("none");
    expect(dom.dupBtn.classList.contains("disabled")).toBe(true);
    dom.form.remove();
  });

  it("sends POST with subject and description to duplicate check endpoint", async () => {
    const dom = createDuplicateCheckDOM();
    dom.descTextarea.value = "test description";
    dom.subjectInput.value = "test subject";
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      text: () => Promise.resolve("<div>results</div>"),
    });
    vi.stubGlobal("fetch", fetchMock);
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    dom.dupBtn.click();
    expect(fetchMock).toHaveBeenCalledWith(
      "/projects/1/ai_helper/check_duplicates",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({
          subject: "test subject",
          description: "test description",
        }),
      })
    );
    dom.form.remove();
  });

  it("displays returned HTML on success", async () => {
    const dom = createDuplicateCheckDOM();
    dom.descTextarea.value = "test";
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      text: () => Promise.resolve("<div>duplicate results</div>"),
    }));
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    dom.dupBtn.click();
    await vi.waitFor(() => {
      expect(dom.dupResults.style.display).toBe("block");
    });
    dom.form.remove();
  });

  it("shows error message on fetch failure", async () => {
    const dom = createDuplicateCheckDOM();
    dom.descTextarea.value = "test";
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("Network error")));
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    dom.dupBtn.click();
    await vi.waitFor(() => {
      expect(dom.dupResults.style.display).toBe("block");
      expect(dom.dupResults.querySelector(".ai-helper-error").textContent).toBe("Network error");
    });
    dom.form.remove();
  });

  it("handles non-ok response with error from JSON", async () => {
    const dom = createDuplicateCheckDOM();
    dom.descTextarea.value = "test";
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: false,
      json: () => Promise.resolve({ error: "Custom error" }),
    }));
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    dom.dupBtn.click();
    await vi.waitFor(() => {
      expect(dom.dupResults.querySelector(".ai-helper-error").textContent).toBe("Custom error");
    });
    dom.form.remove();
  });

  it("re-enables button and hides loading after fetch completes", async () => {
    const dom = createDuplicateCheckDOM();
    dom.descTextarea.value = "test";
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      text: () => Promise.resolve("<div>ok</div>"),
    }));
    await loadScript("assets/javascripts/ai_helper_issue_autocompletion");
    await vi.advanceTimersByTimeAsync(600);

    dom.dupBtn.click();
    await vi.waitFor(() => {
      expect(dom.dupLoading.style.display).toBe("none");
      expect(dom.dupBtn.classList.contains("disabled")).toBe(false);
    });
    dom.form.remove();
  });
});
