import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";
import { loadScriptAndFireDOMContentLoaded } from "../support/dom_content_loaded.js";
import { createJstEditor } from "../support/jst_editor.js";

// --- T020: Characterization tests for shared/_textarea_overlay.html.erb extraction ---

describe("initializeIssueCompletion (from shared/_textarea_overlay.html.erb)", () => {
  let container;
  let autoCompletionMock;
  let cleanup;
  // Forms built by createJstIssueDOM; removed in afterEach so a failing
  // assertion cannot leave its editors behind for the next test.
  let jstForms = [];

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

  /**
   * Builds the DOM the way Redmine and the plugin ERB really render it:
   * app/views/issues/_form.html.erb puts the description textarea in
   * `span#issue_description_and_toolbar`, app/views/issues/_edit.html.erb puts
   * the notes textarea in `fieldset#add_notes`, and Redmine's jsToolBar wraps
   * each textarea in `div.jstBlock` (see support/jst_editor.js). The AI Helper
   * containers come from the `view_issues_form_details_bottom` hook, so they
   * start outside the editors and the script moves them. As in
   * shared/_textarea_overlay.html.erb, the duplicate-check container exists
   * only for a new issue and the notes container only for a persisted one.
   * @param {object} options
   * @param {boolean} options.persisted true for the edit form of an existing issue
   * @returns {object} the created elements
   */
  function createJstIssueDOM({ persisted = false } = {}) {
    const form = document.createElement("div");

    const descWrapper = document.createElement("span");
    descWrapper.id = "issue_description_and_toolbar";
    const desc = createJstEditor("issue_description");
    descWrapper.appendChild(desc.block);
    const descParagraph = document.createElement("p");
    descParagraph.appendChild(descWrapper);
    form.appendChild(descParagraph);

    let notes = null;
    if (persisted) {
      const fieldset = document.createElement("fieldset");
      fieldset.id = "add_notes";
      notes = createJstEditor("issue_notes");
      fieldset.appendChild(notes.block);
      form.appendChild(fieldset);
    }

    const hookArea = document.createElement("div");
    const buildContainer = (id) => {
      const el = document.createElement("div");
      el.id = id;
      el.style.display = "none";
      hookArea.appendChild(el);
      return el;
    };
    const descContainer = buildContainer("ai-helper-description-checkbox-container");
    const dupContainer = persisted ? null : buildContainer("ai-helper-duplicate-check-container");
    const notesContainer = persisted ? buildContainer("ai-helper-notes-checkbox-container") : null;
    form.appendChild(hookArea);

    document.body.appendChild(form);
    jstForms.push(form);
    return { form, descWrapper, desc, notes, descContainer, dupContainer, notesContainer };
  }

  /**
   * Builds the DOM of a form without Redmine's wiki toolbar (text format
   * "none"): the description textarea stands alone and the AI Helper
   * container is rendered elsewhere by the hook.
   * @returns {object} the created elements
   */
  function createPlainIssueDOM() {
    const form = document.createElement("div");
    const textarea = document.createElement("textarea");
    textarea.id = "issue_description";
    const paragraph = document.createElement("p");
    paragraph.appendChild(textarea);
    form.appendChild(paragraph);

    const descContainer = document.createElement("div");
    descContainer.id = "ai-helper-description-checkbox-container";
    descContainer.style.display = "none";
    const hookArea = document.createElement("div");
    hookArea.appendChild(descContainer);
    form.appendChild(hookArea);

    document.body.appendChild(form);
    jstForms.push(form);
    return { form, textarea, descContainer };
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

  beforeEach(async () => {
    // Loaded by _html_header.html.erb before the autocompletion scripts
    await loadScript("assets/javascripts/shared/ai_helper_editor_controls");
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
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    vi.useRealTimers();
    jstForms.forEach((form) => form.remove());
    jstForms = [];
    document
      .querySelectorAll(
        "#ai-helper-issue-textarea-overlay, #issue_description, #issue_notes, #ai-helper-description-checkbox-container, #ai-helper-notes-checkbox-container, #ai-helper-duplicate-check-container, #ai-helper-duplicate-check-btn, #ai-helper-duplicate-check-results, #ai-helper-duplicate-check-loading, #issue_subject, meta[name=csrf-token]"
      )
      .forEach((el) => el.remove());
    vi.unstubAllGlobals();
    delete window.aiHelperInstances;
    delete window.aiHelperAutoCompletionInitialized;
    delete window.AiHelperEditorControls;
  });

  it("creates an AiHelperAutoCompletion for description textarea", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    const dom = createIssueDOM();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

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
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(window.aiHelperInstances.autoCompletion).toBe(mockInstance);
    dom.form.remove();
  });

  it("moves the description checkbox container right after the textarea when there is no wiki toolbar (FR-005)", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    const dom = createPlainIssueDOM();
    expect(dom.textarea.nextElementSibling).toBeNull();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(dom.textarea.nextElementSibling).toBe(dom.descContainer);
    expect(dom.descContainer.style.display).toBe("block");
  });

  it("places the description checkbox container after .jstBlock, not inside .jstEditor (issue #541)", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    const dom = createJstIssueDOM();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(dom.desc.block.nextElementSibling).toBe(dom.descContainer);
    expect(dom.desc.editor.contains(dom.descContainer)).toBe(false);
  });

  it("places both checkbox containers after their own .jstBlock on the issue edit form (issue #541)", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    container.dataset.config = createConfig({
      isPersistedIssue: true,
      notesEndpoint: "/projects/1/ai_helper/issues/5/suggest_completion",
      issueId: "5",
    });
    const dom = createJstIssueDOM({ persisted: true });
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(dom.notes.block.nextElementSibling).toBe(dom.notesContainer);
    expect(dom.notes.editor.contains(dom.notesContainer)).toBe(false);
    expect(dom.notesContainer.style.display).toBe("block");
    expect(dom.desc.block.nextElementSibling).toBe(dom.descContainer);
    expect(dom.desc.editor.contains(dom.descContainer)).toBe(false);
  });

  it("keeps the description checkbox inside the collapsed description wrapper on the issue edit form", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    container.dataset.config = createConfig({
      isPersistedIssue: true,
      notesEndpoint: "/projects/1/ai_helper/issues/5/suggest_completion",
      issueId: "5",
    });
    const dom = createJstIssueDOM({ persisted: true });
    // app/views/issues/_form.html.erb hides the editor of a persisted issue until the edit link is clicked
    dom.descWrapper.style.display = "none";
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(dom.descContainer.parentNode).toBe(dom.descWrapper);
    expect(dom.desc.block.nextElementSibling).toBe(dom.descContainer);
    expect(dom.descWrapper.style.display).toBe("none");
  });

  it("keeps the order editor, completion checkbox, duplicate-check link on a new issue (FR-004)", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    const dom = createJstIssueDOM();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(dom.desc.block.nextElementSibling).toBe(dom.descContainer);
    expect(dom.descContainer.nextElementSibling).toBe(dom.dupContainer);
    expect(dom.dupContainer.style.display).toBe("block");
    expect(dom.desc.editor.contains(dom.dupContainer)).toBe(false);
  });

  it("does not reinitialize if aiHelperAutoCompletionInitialized is true", async () => {
    window.aiHelperAutoCompletionInitialized = true;
    const dom = createIssueDOM();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

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
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

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
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

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
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(window.aiHelperInstances.notesAutoCompletion).toBe(mockInstance);
    dom.form.remove();
  });

  it("does nothing when container does not exist", async () => {
    container.remove();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(autoCompletionMock).not.toHaveBeenCalled();
  });

  it("does nothing when description textarea does not exist and isPersistedIssue is false", async () => {
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(autoCompletionMock).not.toHaveBeenCalled();
  });
});

describe("initializeIssueTypoChecker (from shared/_textarea_overlay.html.erb)", () => {
  let container;
  let cleanup;

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
    await loadScript("assets/javascripts/typo_checker/ai_helper_typo_checker");

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
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    document
      .querySelectorAll(
        "#ai-helper-issue-typo-overlay, #ai-helper-issue-textarea-overlay, #issue_description, #issue_notes, .ai-helper-typo-accept-btn-template, .ai-helper-typo-reject-btn-template, #ai-helper-typo-control-panel-description, #ai-helper-typo-control-panel-notes, meta[name=csrf-token]"
      )
      .forEach((el) => el.remove());
  });

  it("creates typo checkers for both description and notes textareas", async () => {
    const dom = createIssueTypoDOM();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(dom.descTextarea.classList.contains("ai-helper-textarea-positioned")).toBe(true);
    expect(dom.notesTextarea.classList.contains("ai-helper-textarea-positioned")).toBe(true);
    dom.form.remove();
  });

  it("does nothing when container does not exist", async () => {
    container.remove();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    // No error thrown
  });
});

describe("initializeAssignmentSuggestion (from shared/_textarea_overlay.html.erb)", () => {
  let container;
  let assignmentMock;
  let cleanup;

  beforeEach(() => {
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
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    document
      .querySelectorAll(
        "#ai-helper-issue-textarea-overlay, #issue_assigned_to_id"
      )
      .forEach((el) => el.remove());
    vi.unstubAllGlobals();
  });

  it("creates an AiHelperAssignmentSuggestion when select and container exist", async () => {
    assignmentMock.mockImplementation(function() { this.init = vi.fn(); });
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(assignmentMock).toHaveBeenCalledTimes(1);
    const callArgs = assignmentMock.mock.calls[0][0];
    expect(callArgs.endpoint).toBe("/projects/1/ai_helper/suggest_assignees");
    expect(callArgs.labels.linkLabel).toBe("Suggest");
  });

  it("does nothing when AiHelperAssignmentSuggestion is undefined", async () => {
    vi.unstubAllGlobals();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    // No error thrown
  });

  it("does nothing when assigned_to select does not exist", async () => {
    document.getElementById("issue_assigned_to_id").remove();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(assignmentMock).not.toHaveBeenCalled();
  });
});

describe("Duplicate check (from shared/_textarea_overlay.html.erb)", () => {
  let container;
  let cleanup;

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

  beforeEach(async () => {
    // Loaded by _html_header.html.erb before the autocompletion scripts
    await loadScript("assets/javascripts/shared/ai_helper_editor_controls");
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
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    document
      .querySelectorAll(
        "#ai-helper-issue-textarea-overlay, #issue_description, #ai-helper-description-checkbox-container, #ai-helper-duplicate-check-container, #issue_subject, meta[name=csrf-token]"
      )
      .forEach((el) => el.remove());
    vi.unstubAllGlobals();
    delete window.aiHelperInstances;
    delete window.aiHelperAutoCompletionInitialized;
    delete window.AiHelperEditorControls;
  });

  it("shows alert when subject and description are empty", async () => {
    const alertMock = vi.fn();
    vi.stubGlobal("alert", alertMock);
    const dom = createDuplicateCheckDOM();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

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
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

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
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

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
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

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
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

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
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

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
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    dom.dupBtn.click();
    await vi.waitFor(() => {
      expect(dom.dupLoading.style.display).toBe("none");
      expect(dom.dupBtn.classList.contains("disabled")).toBe(false);
    });
    dom.form.remove();
  });
});
