import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";
import { loadScriptAndFireDOMContentLoaded } from "../support/dom_content_loaded.js";
import { createJstEditor } from "../support/jst_editor.js";
import { flushPromises, installFetchStub } from "../support/fetch_stub.js";

// ============================================================
// Fixture builders — the DOM is transcribed from the production
// templates (CRF-042/CRF-077):
// - app/views/issues/_form.html.erb renders the description in
//   span#issue_description_and_toolbar inside #all_attributes and calls
//   view_issues_form_details_bottom at its end, so every AI Helper
//   container of the issue form sits inside #all_attributes.
// - app/views/issues/_edit.html.erb renders fieldset#add_notes OUTSIDE
//   #all_attributes; its view_issues_edit_notes_bottom hook renders
//   ai_helper/issues/_notes_controls.html.erb (the notes containers).
// - app/views/ai_helper/shared/_textarea_overlay.html.erb renders the
//   duplicate-check container only for a new issue.
// Redmine's replaceIssueFormWith re-renders by emptying #all_attributes
// and prepending the fresh form partial, so rerenderAllAttributes()
// reproduces exactly that operation.
// ============================================================

/** Config JSON as rendered into #ai-helper-issue-textarea-overlay[data-config]. */
function createConfig(overrides = {}) {
  const persisted = overrides.isPersistedIssue ?? false;
  return JSON.stringify({
    descriptionEndpoint: persisted
      ? "/projects/1/ai_helper/issue/5/suggest_completion"
      : "/projects/1/ai_helper/issue/new/suggest_completion",
    userId: "1",
    isPersistedIssue: persisted,
    issueId: persisted ? "5" : null,
    projectId: "1",
    debounceDelay: 500,
    minLength: 5,
    suggestionColor: "#888888",
    duplicateCheckEndpoint: "/projects/1/ai_helper/check_duplicates",
    notesEndpoint: persisted ? "/projects/1/ai_helper/issue/5/suggest_completion" : "#",
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

/** Assignment config JSON as rendered into data-assignment-config. */
function createAssignmentConfig(overrides = {}) {
  return JSON.stringify({
    endpoint: "/projects/1/ai_helper/issue/new/suggest_assignees",
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
    ...overrides,
  });
}

/** The hidden accept/reject button templates rendered by the overlay partial. */
function buildTypoButtonTemplates() {
  const templates = document.createElement("div");
  templates.id = "ai-helper-typo-button-templates";
  templates.style.display = "none";
  const accept = document.createElement("span");
  accept.className = "ai-helper-typo-accept-btn-template";
  accept.innerHTML = "✓";
  templates.appendChild(accept);
  const reject = document.createElement("span");
  reject.className = "ai-helper-typo-reject-btn-template";
  reject.innerHTML = "✗";
  templates.appendChild(reject);
  return templates;
}

function buildCheckboxContainer(id) {
  const container = document.createElement("div");
  container.id = id;
  container.className = "ai-helper-autocompletion-controls";
  container.style.display = "none";
  return container;
}

/**
 * A field's checkbox container: toggle + typo check button (per the ERB). The
 * description one is rendered by shared/_textarea_overlay.html.erb, the notes
 * one by issues/_notes_controls.html.erb.
 * @param {string} field "description" or "notes"
 * @returns {object} the container, toggle and check button elements
 */
function buildFieldCheckboxContainer(field) {
  const container = buildCheckboxContainer(`ai-helper-${field}-checkbox-container`);
  const row = document.createElement("div");
  const span = document.createElement("span");
  const toggle = document.createElement("input");
  toggle.type = "checkbox";
  toggle.id = `ai-helper-autocompletion-${field}-toggle`;
  const label = document.createElement("label");
  label.htmlFor = toggle.id;
  span.appendChild(toggle);
  span.appendChild(label);
  row.appendChild(span);
  const checkButton = document.createElement("a");
  checkButton.id = `ai-helper-typo-check-${field}-btn`;
  row.appendChild(checkButton);
  container.appendChild(row);
  return { container, toggle, checkButton };
}

/** The duplicate-check container, rendered for a new issue when vector search is on. */
function buildDuplicateCheckContainer() {
  const container = buildCheckboxContainer("ai-helper-duplicate-check-container");
  const button = document.createElement("a");
  button.id = "ai-helper-duplicate-check-btn";
  container.appendChild(button);
  const results = document.createElement("div");
  results.id = "ai-helper-duplicate-check-results";
  results.style.display = "none";
  container.appendChild(results);
  const loading = document.createElement("div");
  loading.id = "ai-helper-duplicate-check-loading";
  loading.style.display = "none";
  container.appendChild(loading);
  return { container, button, results, loading };
}

/** A typo control panel with apply-all/close buttons (per the ERB). */
function buildTypoControlPanel(id) {
  const panel = document.createElement("div");
  panel.id = id;
  panel.className = "ai-helper-typo-control-panel";
  panel.style.display = "none";
  const applyAll = document.createElement("button");
  applyAll.type = "button";
  applyAll.className = "ai-helper-typo-apply-all-btn";
  panel.appendChild(applyAll);
  const close = document.createElement("button");
  close.type = "button";
  close.className = "ai-helper-typo-close-btn";
  panel.appendChild(close);
  return panel;
}

/** #ai-helper-issue-typo-overlay with its data-config. */
function buildTypoOverlay() {
  const overlay = document.createElement("div");
  overlay.id = "ai-helper-issue-typo-overlay";
  overlay.dataset.config = JSON.stringify({
    endpoint: "/projects/1/ai_helper/check_typos",
    labels: {
      suggestionsTitle: "Suggestions",
      noSuggestions: "No typos",
      checkButton: "Check",
      checking: "Checking...",
      acceptSuggestion: "Accept",
      dismissSuggestion: "Reject",
      acceptAll: "Accept All",
      dismissAll: "Dismiss All",
      errorOccurred: "Error",
      correctionTooltip: "Correction",
      applyFailed: "Failed",
    },
  });
  return overlay;
}

/** #ai-helper-issue-textarea-overlay with both configs. */
function buildConfigOverlay(overrides = {}) {
  const overlay = document.createElement("div");
  overlay.id = "ai-helper-issue-textarea-overlay";
  overlay.dataset.config = createConfig(overrides.config ?? {});
  overlay.dataset.assignmentConfig = createAssignmentConfig(overrides.assignmentConfig ?? {});
  return overlay;
}

/**
 * The content of #all_attributes: the form fields rendered by
 * issues/_form.html.erb (subject, then description, then the attribute
 * selects inside div#attributes) plus, when the AI Helper module is enabled
 * (`hookOutput`), the output of view_issues_form_details_bottom.
 * @param {HTMLElement} into the #all_attributes element
 * @param {object} options
 * @param {boolean} options.persisted true for the edit form of a persisted issue
 * @param {boolean} options.hookOutput false for a project with the module disabled
 * @param {boolean} options.withDescription false when the user may not edit the
 *   description (`safe_attribute?('description')`, _form.html.erb:32): the
 *   textarea is then not rendered at all
 * @param {boolean} options.descriptionHidden true to hide the description
 *   editor the way the edit form does until the edit link is clicked
 *   (`display:none` on span#issue_description_and_toolbar, _form.html.erb:35-36)
 * @returns {object} the created elements
 */
function buildFormDetails(into, { persisted = false, hookOutput = true, withDescription = true, descriptionHidden = false } = {}) {
  const created = {};

  const subjectP = document.createElement("p");
  created.subject = document.createElement("input");
  created.subject.id = "issue_subject";
  subjectP.appendChild(created.subject);
  into.appendChild(subjectP);

  if (withDescription) {
    const paragraph = document.createElement("p");
    const wrapper = document.createElement("span");
    wrapper.id = "issue_description_and_toolbar";
    if (descriptionHidden) {
      wrapper.style.display = "none";
    }
    created.desc = createJstEditor("issue_description");
    wrapper.appendChild(created.desc.block);
    paragraph.appendChild(wrapper);
    into.appendChild(paragraph);
    created.wrapper = wrapper;
  }

  const attributes = document.createElement("div");
  attributes.id = "attributes";
  const assigneeP = document.createElement("p");
  created.assigneeSelect = document.createElement("select");
  created.assigneeSelect.id = "issue_assigned_to_id";
  const blankOption = document.createElement("option");
  blankOption.value = "";
  created.assigneeSelect.appendChild(blankOption);
  const option = document.createElement("option");
  option.value = "3";
  created.assigneeSelect.appendChild(option);
  assigneeP.appendChild(created.assigneeSelect);
  attributes.appendChild(assigneeP);
  into.appendChild(attributes);

  if (hookOutput) {
    const descControls = buildFieldCheckboxContainer("description");
    into.appendChild(descControls.container);
    created.descControls = descControls;
    if (!persisted) {
      created.duplicate = buildDuplicateCheckContainer();
      into.appendChild(created.duplicate.container);
    }
    into.appendChild(buildTypoControlPanel("ai-helper-typo-control-panel-description"));
    into.appendChild(buildTypoOverlay());
    created.overlay = buildConfigOverlay({ config: { isPersistedIssue: persisted } });
    into.appendChild(created.overlay);
    into.appendChild(buildTypoButtonTemplates());
  }
  return created;
}

/**
 * fieldset#add_notes as issues/_edit.html.erb renders it: the notes editor,
 * the wiki toolbar script, the private-notes checkbox and label, then the
 * view_issues_edit_notes_bottom hook output (the reply fieldset of
 * ai_helper/issues/_form, then _notes_controls: checkbox container + typo
 * panel). The controls therefore start FAR from the editor and the script has
 * to move them next to it.
 * @param {object} options
 * @param {boolean} options.controls false when the module is disabled for the issue's project
 * @returns {object} the created elements
 */
function buildAddNotes({ controls = true } = {}) {
  const created = {};
  const addNotes = document.createElement("fieldset");
  addNotes.id = "add_notes";
  created.notes = createJstEditor("issue_notes");
  addNotes.appendChild(created.notes.block);

  const toolbarScript = document.createElement("script");
  addNotes.appendChild(toolbarScript);
  const privateNotes = document.createElement("input");
  privateNotes.type = "checkbox";
  privateNotes.id = "issue_private_notes";
  addNotes.appendChild(privateNotes);
  const privateLabel = document.createElement("label");
  privateLabel.htmlFor = "issue_private_notes";
  addNotes.appendChild(privateLabel);
  const reply = document.createElement("fieldset");
  reply.id = "ai-helper-issue-reply-fieldset";
  addNotes.appendChild(reply);

  if (controls) {
    created.notesControls = buildFieldCheckboxContainer("notes");
    addNotes.appendChild(created.notesControls.container);
    created.notesTypoPanel = buildTypoControlPanel("ai-helper-typo-control-panel-notes");
    addNotes.appendChild(created.notesTypoPanel);
  }
  created.addNotes = addNotes;
  return created;
}

/**
 * Builds the issue page the way Redmine and the plugin hooks render it.
 * @param {object} options
 * @param {boolean} options.persisted true for the edit form of a persisted issue
 * @param {boolean} options.hookOutput false for a project with the module disabled
 * @param {boolean} options.withAllAttributes false on pages without the form
 * @param {boolean} options.notesControls false when the notes controls are not rendered
 * @param {boolean} options.descriptionHidden hide the description editor like the edit form does
 * @returns {object} the created elements
 */
function buildIssueForm({ persisted = false, hookOutput = true, withAllAttributes = true, notesControls = true, descriptionHidden = false } = {}) {
  const form = document.createElement("div");
  const created = { form };

  if (withAllAttributes) {
    const allAttributes = document.createElement("div");
    allAttributes.id = "all_attributes";
    form.appendChild(allAttributes);
    Object.assign(created, buildFormDetails(allAttributes, { persisted, hookOutput, descriptionHidden }));
    created.allAttributes = allAttributes;
  } else {
    Object.assign(created, buildFormDetails(form, { persisted, hookOutput, descriptionHidden }));
  }

  if (persisted) {
    // fieldset#add_notes sits outside #all_attributes (issues/_edit.html.erb)
    Object.assign(created, buildAddNotes({ controls: notesControls }));
    form.appendChild(created.addNotes);
  }

  document.body.appendChild(form);
  return created;
}

/**
 * Re-renders #all_attributes the way Redmine's replaceIssueFormWith does:
 * removes every child and puts the fresh form partial content in.
 * @param {object} options passed through to buildFormDetails
 * @returns {object} the freshly created elements
 */
function rerenderAllAttributes(options = {}) {
  const allAttributes = document.getElementById("all_attributes");
  while (allAttributes.firstChild) {
    allAttributes.firstChild.remove();
  }
  return buildFormDetails(allAttributes, options);
}

/** Build a DOMException-like AbortError, matching what fetch rejects with. */
function buildAbortError() {
  const error = new Error("The user aborted a request.");
  error.name = "AbortError";
  return error;
}

/** Mock class for AiHelperAutoCompletion recording every instance. */
function stubAutoCompletion() {
  const instances = [];
  const Mock = function(textarea, options) {
    this.destroy = vi.fn();
    this.textarea = textarea;
    this.options = options;
    instances.push(this);
  };
  Mock.prototype.init = vi.fn();
  Mock.prototype.clearSuggestion = vi.fn();
  vi.stubGlobal("AiHelperAutoCompletion", Mock);
  return { Mock, instances };
}

/** Mock class for AiHelperAssignmentSuggestion recording every instance. */
function stubAssignmentSuggestion() {
  const instances = [];
  const Mock = function(options) {
    this.init = vi.fn();
    this.destroy = vi.fn();
    this.options = options;
    instances.push(this);
  };
  vi.stubGlobal("AiHelperAssignmentSuggestion", Mock);
  return { Mock, instances };
}

/**
 * Record the document-level listeners added/removed while active, without
 * changing the behaviour (the originals still run).
 */
function trackDocumentListeners() {
  const added = [];
  const removed = [];
  const originalAdd = Document.prototype.addEventListener;
  const originalRemove = Document.prototype.removeEventListener;
  vi.spyOn(document, "addEventListener").mockImplementation(function(type, listener, options) {
    added.push({ type, listener, options });
    return originalAdd.call(document, type, listener, options);
  });
  vi.spyOn(document, "removeEventListener").mockImplementation(function(type, listener, options) {
    removed.push({ type, listener, options });
    return originalRemove.call(document, type, listener, options);
  });
  return { added, removed };
}

// ============================================================
// Page-bootstrap behaviour (characterization: the module wires the
// issue form aids at DOMContentLoaded, like the extraction it came from)
// ============================================================

describe("issue form aids page bootstrap", () => {
  let autoCompletionMock;
  let cleanup;
  // Forms built by the fixtures; removed in afterEach so a failing
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
   * only for a new issue; the notes containers now render in
   * fieldset#add_notes via issues/_notes_controls.html.erb.
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
      // issues/_edit.html.erb: toolbar script, private-notes checkbox and the
      // reply fieldset sit between the editor and the hook's notes controls
      fieldset.appendChild(document.createElement("script"));
      const privateNotes = document.createElement("input");
      privateNotes.type = "checkbox";
      fieldset.appendChild(privateNotes);
      fieldset.appendChild(document.createElement("fieldset"));
      const notesContainer = document.createElement("div");
      notesContainer.id = "ai-helper-notes-checkbox-container";
      notesContainer.style.display = "none";
      fieldset.appendChild(notesContainer);
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
    form.appendChild(hookArea);

    document.body.appendChild(form);
    jstForms.push(form);
    return { form, descWrapper, desc, notes, descContainer, dupContainer };
  }

  /**
   * Builds the DOM of a form without Redmine's wiki toolbar (text format
   * "none"): the description textarea stands alone and the AI Helper
   * container is rendered elsewhere by the hook.
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

  beforeEach(async () => {
    // Loaded by _html_header.html.erb before the autocompletion scripts
    await loadScript("assets/javascripts/shared/ai_helper_editor_controls");
    autoCompletionMock = vi.fn();
    vi.stubGlobal("AiHelperAutoCompletion", autoCompletionMock);

    const meta = document.createElement("meta");
    meta.name = "csrf-token";
    meta.content = "test-csrf-token";
    document.head.appendChild(meta);

    const container = document.createElement("div");
    container.id = "ai-helper-issue-textarea-overlay";
    container.dataset.config = createConfig();
    document.body.appendChild(container);
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
    document.getElementById("ai-helper-issue-textarea-overlay").dataset.config = createConfig({
      isPersistedIssue: true,
      notesEndpoint: "/projects/1/ai_helper/issues/5/suggest_completion",
      issueId: "5",
    });
    const dom = createJstIssueDOM({ persisted: true });
    const notesContainer = document.getElementById("ai-helper-notes-checkbox-container");
    // Before the script runs the container is NOT right below the editor
    expect(dom.notes.block.nextElementSibling).not.toBe(notesContainer);
    expect(dom.desc.block.nextElementSibling).toBeNull();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(dom.notes.block.nextElementSibling).toBe(notesContainer);
    expect(dom.notes.editor.contains(notesContainer)).toBe(false);
    expect(notesContainer.style.display).toBe("block");
    expect(dom.desc.block.nextElementSibling).toBe(dom.descContainer);
    expect(dom.desc.editor.contains(dom.descContainer)).toBe(false);
  });

  it("keeps the description checkbox inside the collapsed description wrapper on the issue edit form", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    document.getElementById("ai-helper-issue-textarea-overlay").dataset.config = createConfig({
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

  it("does not set the global aiHelperAutoCompletionInitialized flag (abolished, R-003)", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    const dom = createIssueDOM();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(window.aiHelperAutoCompletionInitialized).toBeUndefined();
    dom.form.remove();
  });

  it("creates notes autocompletion when isPersistedIssue is true and notes textarea exists", async () => {
    autoCompletionMock.mockImplementation(function() { this.init = vi.fn(); });
    document.getElementById("ai-helper-issue-textarea-overlay").dataset.config = createConfig({
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
    document.getElementById("ai-helper-issue-textarea-overlay").dataset.config = createConfig({ isPersistedIssue: false });
    const dom = createIssueDOM();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(autoCompletionMock).toHaveBeenCalledTimes(1);
    dom.form.remove();
  });

  it("stores notesAutoCompletion on window.aiHelperInstances for persisted issues", async () => {
    const mockInstance = { init: vi.fn(), clearSuggestion: vi.fn() };
    autoCompletionMock.mockImplementation(function() { return mockInstance; });
    document.getElementById("ai-helper-issue-textarea-overlay").dataset.config = createConfig({
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
    document.getElementById("ai-helper-issue-textarea-overlay").remove();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(autoCompletionMock).not.toHaveBeenCalled();
  });

  it("does nothing when description textarea does not exist and isPersistedIssue is false", async () => {
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(autoCompletionMock).not.toHaveBeenCalled();
  });
});

describe("issue typo checkers page bootstrap", () => {
  let cleanup;

  beforeEach(async () => {
    await loadScript("assets/javascripts/shared/ai_helper_editor_controls");
    await loadScript("assets/javascripts/typo_checker/ai_helper_typo_checker");
    const acMock = vi.fn();
    acMock.mockImplementation(function() { this.init = vi.fn(); });
    vi.stubGlobal("AiHelperAutoCompletion", acMock);
    vi.stubGlobal("AiHelperAssignmentSuggestion", vi.fn().mockImplementation(function() { this.init = vi.fn(); }));

    const meta = document.createElement("meta");
    meta.name = "csrf-token";
    meta.content = "test-csrf-token";
    document.head.appendChild(meta);
  });

  afterEach(() => {
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    document.body.innerHTML = "";
    document.head.querySelectorAll('meta[name="csrf-token"]').forEach((el) => el.remove());
    vi.unstubAllGlobals();
    delete window.aiHelperInstances;
    delete window.AiHelperEditorControls;
  });

  it("creates typo checkers for the description and, on a persisted issue, the notes textareas", async () => {
    const dom = buildIssueForm({ persisted: true });
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(dom.desc.textarea.classList.contains("ai-helper-textarea-positioned")).toBe(true);
    expect(dom.notes.textarea.classList.contains("ai-helper-textarea-positioned")).toBe(true);
  });

  it("does not create the notes typo checker on a new issue (no notes editor is rendered)", async () => {
    const dom = buildIssueForm({ persisted: false });
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(dom.desc.textarea.classList.contains("ai-helper-textarea-positioned")).toBe(true);
    expect(document.getElementById("issue_notes")).toBeNull();
  });

  it("does nothing when the typo overlay container does not exist", async () => {
    const dom = buildIssueForm({ persisted: true });
    document.getElementById("ai-helper-issue-typo-overlay").remove();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    expect(dom.desc.textarea.classList.contains("ai-helper-textarea-positioned")).toBe(false);
    expect(dom.notes.textarea.classList.contains("ai-helper-textarea-positioned")).toBe(false);
  });
});

describe("assignment suggestion page bootstrap", () => {
  let assignmentMock;
  let cleanup;

  beforeEach(async () => {
    assignmentMock = vi.fn();
    vi.stubGlobal("AiHelperAssignmentSuggestion", assignmentMock);

    const select = document.createElement("select");
    select.id = "issue_assigned_to_id";
    document.body.appendChild(select);

    const container = document.createElement("div");
    container.id = "ai-helper-issue-textarea-overlay";
    container.dataset.config = createConfig();
    container.dataset.assignmentConfig = createAssignmentConfig();
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
    expect(callArgs.endpoint).toBe("/projects/1/ai_helper/issue/new/suggest_assignees");
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

describe("duplicate check page bootstrap", () => {
  let cleanup;

  beforeEach(async () => {
    // Loaded by _html_header.html.erb before the autocompletion scripts
    await loadScript("assets/javascripts/shared/ai_helper_editor_controls");
    const acMock = vi.fn();
    acMock.mockImplementation(function() { this.init = vi.fn(); });
    vi.stubGlobal("AiHelperAutoCompletion", acMock);

    const meta = document.createElement("meta");
    meta.name = "csrf-token";
    meta.content = "test-csrf-token";
    document.head.appendChild(meta);

    const container = document.createElement("div");
    container.id = "ai-helper-issue-textarea-overlay";
    container.dataset.config = createConfig();
    document.body.appendChild(container);
  });

  afterEach(() => {
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    document.body.innerHTML = "";
    document.head.querySelectorAll('meta[name="csrf-token"]').forEach((el) => el.remove());
    vi.unstubAllGlobals();
    delete window.aiHelperInstances;
    delete window.AiHelperEditorControls;
  });

  function bootstrapDuplicateDOM() {
    const dom = buildIssueForm({ persisted: false });
    return {
      form: dom.form,
      descTextarea: dom.desc.textarea,
      subjectInput: dom.subject,
      dupBtn: dom.duplicate.button,
      dupResults: dom.duplicate.results,
      dupLoading: dom.duplicate.loading,
    };
  }

  it("shows alert when subject and description are empty", async () => {
    const alertMock = vi.fn();
    vi.stubGlobal("alert", alertMock);
    const dom = bootstrapDuplicateDOM();
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    dom.dupBtn.click();
    expect(alertMock).toHaveBeenCalledWith("Please enter subject or description");
  });

  it("shows loading and hides results on click", async () => {
    const dom = bootstrapDuplicateDOM();
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
  });

  it("sends POST with subject and description to duplicate check endpoint", async () => {
    const dom = bootstrapDuplicateDOM();
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
  });

  it("displays returned HTML on success", async () => {
    const dom = bootstrapDuplicateDOM();
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
  });

  it("shows error message on fetch failure", async () => {
    const dom = bootstrapDuplicateDOM();
    dom.descTextarea.value = "test";
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("Network error")));
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    dom.dupBtn.click();
    await vi.waitFor(() => {
      expect(dom.dupResults.style.display).toBe("block");
      expect(dom.dupResults.querySelector(".ai-helper-error").textContent).toBe("Network error");
    });
  });

  it("handles non-ok response with error from JSON", async () => {
    const dom = bootstrapDuplicateDOM();
    dom.descTextarea.value = "test";
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: false,
      status: 422,
      headers: new Headers({ "Content-Type": "application/json; charset=utf-8" }),
      json: () => Promise.resolve({ error: "Custom error" }),
    }));
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    dom.dupBtn.click();
    await vi.waitFor(() => {
      expect(dom.dupResults.querySelector(".ai-helper-error").textContent).toBe("Custom error");
    });
  });

  it("shows the HTTP status when a non-ok response has a non-JSON body (an HTML error page)", async () => {
    const dom = bootstrapDuplicateDOM();
    dom.descTextarea.value = "test";
    const jsonSpy = vi.fn(() => Promise.reject(new SyntaxError("Unexpected token <")));
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: false,
      status: 500,
      statusText: "Internal Server Error",
      headers: new Headers({ "Content-Type": "text/html; charset=utf-8" }),
      json: jsonSpy,
    }));
    vi.spyOn(console, "error").mockImplementation(() => {});
    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    dom.dupBtn.click();
    await vi.waitFor(() => {
      expect(dom.dupResults.querySelector(".ai-helper-error").textContent).toBe("HTTP 500 Internal Server Error");
    });
    expect(jsonSpy).not.toHaveBeenCalled();
  });

  it("re-enables button and hides loading after fetch completes", async () => {
    const dom = bootstrapDuplicateDOM();
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
  });
});

describe("completion request context_type from the issue page entry points (085 US2)", () => {
  let cleanup;
  let jstForms = [];

  beforeEach(async () => {
    // The real completion class, so the request body is the real payload
    await loadScript("assets/javascripts/shared/ai_helper_editor_controls");
    await loadScript("assets/javascripts/autocompletion/ai_helper_auto_completion");
    await loadScript("assets/javascripts/autocompletion/ai_helper_auto_completion_overlay");

    const meta = document.createElement("meta");
    meta.name = "csrf-token";
    meta.content = "test-csrf-token";
    document.head.appendChild(meta);

    const container = document.createElement("div");
    container.id = "ai-helper-issue-textarea-overlay";
    container.dataset.config = createConfig({ isPersistedIssue: true, debounceDelay: 0, minLength: 1 });
    document.body.appendChild(container);
  });

  afterEach(async () => {
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    jstForms.forEach((form) => form.remove());
    jstForms = [];
    document.body.innerHTML = "";
    document.head.querySelectorAll('meta[name="csrf-token"]').forEach((el) => el.remove());
    vi.unstubAllGlobals();
    localStorage.clear();
    delete window.aiHelperInstances;
    delete window.AiHelperEditorControls;
  });

  /** Run the page entry point on a persisted issue and fetch the body sent from one field. */
  async function requestBodyFor(textareaId) {
    // The page loads with completion enabled (shared localStorage key, R-009)
    localStorage.setItem("aiHelperAutoCompletion_1", JSON.stringify({ enabled: true }));

    const fetchCalls = [];
    vi.stubGlobal("fetch", vi.fn((url, options) => {
      fetchCalls.push({ url, options });
      return Promise.resolve({
        ok: true,
        status: 200,
        json: () => Promise.resolve({ suggestion: "" }),
      });
    }));

    const desc = createJstEditor("issue_description");
    const notes = createJstEditor("issue_notes");
    const form = document.createElement("form");
    form.appendChild(desc.block);
    form.appendChild(notes.block);
    document.body.appendChild(form);
    jstForms.push(form);

    const descContainer = document.createElement("div");
    descContainer.id = "ai-helper-description-checkbox-container";
    descContainer.innerHTML = '<input type="checkbox" id="ai-helper-autocompletion-description-toggle">';
    descContainer.style.display = "none";
    form.appendChild(descContainer);
    const notesContainer = document.createElement("div");
    notesContainer.id = "ai-helper-notes-checkbox-container";
    notesContainer.innerHTML = '<input type="checkbox" id="ai-helper-autocompletion-notes-toggle">';
    notesContainer.style.display = "none";
    form.appendChild(notesContainer);

    cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");

    const textarea = document.getElementById(textareaId);
    textarea.value = "typed text for the request";
    textarea.dispatchEvent(new Event("input", { bubbles: true }));
    await new Promise((resolve) => setTimeout(resolve, 20));
    await Promise.resolve();

    expect(fetchCalls.length).toBeGreaterThanOrEqual(1);
    return fetchCalls.map((c) => JSON.parse(c.options.body));
  }

  it("sends the new-comment field's request with context_type 'note' (CRF-006)", async () => {
    const bodies = await requestBodyFor("issue_notes");
    expect(bodies.some((b) => b.context_type === "note")).toBe(true);
  });

  it("sends the description field's request with context_type 'description'", async () => {
    const bodies = await requestBodyFor("issue_description");
    expect(bodies.some((b) => b.context_type === "description")).toBe(true);
  });
});

// ============================================================
// AiHelperIssueFormAids — re-render resilience (088-fix-issue-form-rerender)
// ============================================================

describe("AiHelperIssueFormAids", () => {
  let autoCompletion;
  let assignmentSuggestion;
  let errorSpy;
  /** Uncaught errors reported to window (what jsdom does with an observer/listener exception). */
  let windowErrors;
  let stopCollectingWindowErrors;

  /** Import the module fresh; jsdom's readyState is complete, so start() runs at import. */
  async function loadModule() {
    await loadScript("assets/javascripts/autocompletion/ai_helper_issue_autocompletion");
  }

  beforeEach(async () => {
    await loadScript("assets/javascripts/shared/ai_helper_editor_controls");
    autoCompletion = stubAutoCompletion();
    assignmentSuggestion = stubAssignmentSuggestion();

    const meta = document.createElement("meta");
    meta.name = "csrf-token";
    meta.content = "test-csrf-token";
    document.head.appendChild(meta);

    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    windowErrors = [];
    const handler = (event) => {
      event.preventDefault();
      windowErrors.push(event.error);
    };
    window.addEventListener("error", handler);
    stopCollectingWindowErrors = () => window.removeEventListener("error", handler);
  });

  afterEach(() => {
    stopCollectingWindowErrors();
    document.body.innerHTML = "";
    document.head.querySelectorAll('meta[name="csrf-token"]').forEach((el) => el.remove());
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    localStorage.clear();
    delete window.aiHelperInstances;
    delete window.AiHelperEditorControls;
  });

  it("start() registers the config container and creates the description completion, typo checker and assignment suggestion (entryFor)", async () => {
    const dom = buildIssueForm({ persisted: false });
    await loadModule();

    window.AiHelperIssueFormAids.start();

    const entry = window.AiHelperIssueFormAids.entryFor(dom.overlay);
    expect(entry).toBeDefined();
    expect(entry.autoCompletion).toBe(autoCompletion.instances[0]);
    expect(entry.autoCompletion.textarea.id).toBe("issue_description");
    expect(entry.autoCompletion.init).toHaveBeenCalledTimes(1);
    expect(entry.typoChecker).not.toBeNull();
    expect(entry.typoChecker.textarea.id).toBe("issue_description");
    expect(entry.assignmentSuggestion).toBe(assignmentSuggestion.instances[0]);
    expect(entry.duplicateCheckAbort).toBeNull();
    expect(window.aiHelperInstances.autoCompletion).toBe(entry.autoCompletion);
  });

  it("after a re-render the aids are attached to the new config container and aiHelperInstances.autoCompletion points at the new instance", async () => {
    const dom = buildIssueForm({ persisted: false });
    await loadModule();
    window.AiHelperIssueFormAids.start();
    const firstEntry = window.AiHelperIssueFormAids.entryFor(dom.overlay);
    const firstInstance = window.aiHelperInstances.autoCompletion;

    rerenderAllAttributes({ persisted: false, hookOutput: true });
    await flushPromises();

    const secondOverlay = document.getElementById("ai-helper-issue-textarea-overlay");
    expect(secondOverlay).not.toBe(dom.overlay);
    const secondEntry = window.AiHelperIssueFormAids.entryFor(secondOverlay);
    expect(secondEntry).toBeDefined();
    expect(secondEntry.autoCompletion).not.toBe(firstEntry.autoCompletion);
    expect(firstEntry.autoCompletion.destroy).toHaveBeenCalled();
    expect(window.AiHelperIssueFormAids.entryFor(dom.overlay)).toBeUndefined();
    expect(window.aiHelperInstances.autoCompletion).toBe(secondEntry.autoCompletion);
    expect(window.aiHelperInstances.autoCompletion).not.toBe(firstInstance);
  });

  it("scanning the same render twice creates no second set of aids (FR-003)", async () => {
    buildIssueForm({ persisted: false });
    await loadModule();
    window.AiHelperIssueFormAids.start();
    const countAfterStart = autoCompletion.instances.length;

    window.AiHelperIssueFormAids.scan(document);
    window.AiHelperIssueFormAids.scan(document.getElementById("all_attributes"));

    expect(autoCompletion.instances.length).toBe(countAfterStart);
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it("scan(root) covers a root that is itself the config container (CRF-049)", async () => {
    const dom = buildIssueForm({ persisted: false });
    await loadModule();

    window.AiHelperIssueFormAids.scan(dom.overlay);

    expect(window.AiHelperIssueFormAids.entryFor(dom.overlay)).toBeDefined();
    expect(autoCompletion.instances.length).toBe(1);
  });

  it("attaches no observer on a page without #all_attributes", async () => {
    const observers = [];
    class FakeObserver {
      constructor() {
        this.disconnect = vi.fn();
        this.observe = vi.fn();
        observers.push(this);
      }
    }
    vi.stubGlobal("MutationObserver", FakeObserver);

    // A page where the hook rendered the overlay but Redmine has no form
    // re-render area (withAllAttributes: false)
    const dom = buildIssueForm({ persisted: false, withAllAttributes: false });
    await loadModule();
    window.AiHelperIssueFormAids.start();

    expect(observers).toHaveLength(0);
    expect(window.AiHelperIssueFormAids.entryFor(dom.overlay)).toBeDefined();

    // Without the observer, a detached container is not released by mutations
    dom.overlay.remove();
    document.body.appendChild(document.createElement("div"));
    await flushPromises();
    expect(window.AiHelperIssueFormAids.entryFor(dom.overlay)).toBeDefined();
  });

  it("a second start() disconnects the previous observer", async () => {
    buildIssueForm({ persisted: false });
    const observers = [];
    class FakeObserver {
      constructor() {
        this.disconnect = vi.fn();
        this.observe = vi.fn();
        observers.push(this);
      }
    }
    vi.stubGlobal("MutationObserver", FakeObserver);

    await loadModule();
    // The import already ran the first start(); this is the second one
    window.AiHelperIssueFormAids.start();

    expect(observers).toHaveLength(2);
    expect(observers[0].disconnect).toHaveBeenCalledTimes(1);
    expect(observers[1].disconnect).not.toHaveBeenCalled();
  });

  // --- Release of detached renders (R-005) ---

  it("releasing a detached render destroys its completion and typo checker and removes the document keydown/click listeners (FR-009)", async () => {
    const dom = buildIssueForm({ persisted: false });
    await loadModule();
    const tracked = trackDocumentListeners();
    window.AiHelperIssueFormAids.start();
    const entry = window.AiHelperIssueFormAids.entryFor(dom.overlay);
    const documentListeners = tracked.added.filter((l) => l.type === "keydown" || l.type === "click");

    rerenderAllAttributes({ persisted: false, hookOutput: true });
    await flushPromises();

    expect(entry.autoCompletion.destroy).toHaveBeenCalled();
    expect(entry.typoChecker.destroyed).toBe(true);
    documentListeners.forEach((l) => {
      expect(tracked.removed).toContainEqual(l);
    });
  });

  it("deletes window.aiHelperInstances.autoCompletion when it points at the released completion, then the new render overwrites it", async () => {
    const dom = buildIssueForm({ persisted: false });
    await loadModule();
    window.AiHelperIssueFormAids.start();
    const firstInstance = window.aiHelperInstances.autoCompletion;
    const firstEntry = window.AiHelperIssueFormAids.entryFor(dom.overlay);

    // Detach without a replacement hook output (module disabled): the global
    // reference must be gone before any new attach could overwrite it
    rerenderAllAttributes({ persisted: false, hookOutput: false });
    await flushPromises();
    expect(firstEntry.autoCompletion.destroy).toHaveBeenCalled();
    expect(window.aiHelperInstances.autoCompletion).toBeUndefined();

    // The next enabled render re-creates the global reference
    rerenderAllAttributes({ persisted: false, hookOutput: true });
    await flushPromises();
    expect(window.aiHelperInstances.autoCompletion).toBeDefined();
    expect(window.aiHelperInstances.autoCompletion).not.toBe(firstInstance);
  });

  it("aborts an in-flight duplicate check on re-render and never writes its result into the detached DOM (FR-007)", async () => {
    const dom = buildIssueForm({ persisted: false });
    await loadModule();
    const fetchStub = installFetchStub();
    window.AiHelperIssueFormAids.start();

    const dupBtn = document.getElementById("ai-helper-duplicate-check-btn");
    const dupResults = dom.duplicate.results;
    const dupLoading = dom.duplicate.loading;
    dom.desc.textarea.value = "test";
    dom.subject.value = "subject";
    dupBtn.click();
    expect(fetchStub.calls.length).toBe(1);

    rerenderAllAttributes({ persisted: false, hookOutput: true });
    await flushPromises();

    expect(fetchStub.calls[0].options.signal.aborted).toBe(true);

    fetchStub.calls[0].resolve({ html: "<div>late results</div>" });
    await flushPromises();
    expect(dupResults.innerHTML).toBe("");
    expect(dupResults.style.display).toBe("none");
    // Released: neither the loading indicator nor the button state is
    // rewritten either (FR-007), so they keep the in-flight state
    expect(dupLoading.style.display).toBe("flex");
    expect(dupBtn.classList.contains("disabled")).toBe(true);
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it("an abort-caused AbortError of the duplicate check is neither displayed nor logged (FR-007)", async () => {
    const dom = buildIssueForm({ persisted: false });
    await loadModule();
    const fetchStub = installFetchStub();
    window.AiHelperIssueFormAids.start();

    dom.subject.value = "subject";
    document.getElementById("ai-helper-duplicate-check-btn").click();
    expect(fetchStub.calls.length).toBe(1);

    rerenderAllAttributes({ persisted: false, hookOutput: true });
    await flushPromises();

    fetchStub.calls[0].reject(buildAbortError());
    await flushPromises();
    expect(errorSpy).not.toHaveBeenCalled();
    expect(dom.duplicate.results.querySelector(".ai-helper-error")).toBeNull();
  });

  // --- Stale responses of the assignment suggestion across a re-render ---

  it("an assignment suggestion response in flight across a re-render reaches neither panel nor the new form (FR-007)", async () => {
    const dom = buildIssueForm({ persisted: false });
    await loadScript("assets/javascripts/autocompletion/ai_helper_assignment_suggestion");
    await loadModule();
    const fetchStub = installFetchStub();
    window.AiHelperIssueFormAids.start();

    dom.subject.value = "subject";
    const link = document.querySelector(".ai-helper-suggest-assignee-link");
    link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    expect(fetchStub.calls.length).toBe(1);
    expect(document.querySelector(".ai-helper-suggest-assignee-panel")).not.toBeNull();

    rerenderAllAttributes({ persisted: false, hookOutput: true });
    await flushPromises();
    expect(fetchStub.calls[0].options.signal.aborted).toBe(true);

    fetchStub.calls[0].resolve({ html: '<a href="#" class="ai-helper-suggest-assignee-user" data-user-id="3">Old Alice</a>' });
    await flushPromises();
    expect(document.querySelector(".ai-helper-suggest-assignee-panel")).toBeNull();
    expect(document.getElementById("issue_assigned_to_id").value).toBe("");
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it("an assignment suggestion panel open across a re-render is closed and exactly one link remains (FR-008)", async () => {
    buildIssueForm({ persisted: false });
    await loadScript("assets/javascripts/autocompletion/ai_helper_assignment_suggestion");
    await loadModule();
    installFetchStub();
    window.AiHelperIssueFormAids.start();

    document.querySelector(".ai-helper-suggest-assignee-link")
      .dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    expect(document.querySelectorAll(".ai-helper-suggest-assignee-panel").length).toBe(1);

    rerenderAllAttributes({ persisted: false, hookOutput: true });
    await flushPromises();

    expect(document.querySelectorAll(".ai-helper-suggest-assignee-panel").length).toBe(0);
    expect(document.querySelectorAll(".ai-helper-suggest-assignee-link").length).toBe(1);
  });

  // --- Failure handling (R-003, CRF-098) ---

  it("attach destroys the parts created so far and rethrows when a later step fails (CRF-098)", async () => {
    await loadModule();
    const dom = buildIssueForm({ persisted: false });
    const typoStub = { initFromConfig: vi.fn(() => { throw new Error("typo boom"); }) };
    vi.stubGlobal("AiHelperTypoChecker", typoStub);

    expect(() => window.AiHelperIssueFormAids.attach(dom.overlay)).toThrow("typo boom");

    expect(autoCompletion.instances[0].destroy).toHaveBeenCalled();
    expect(window.AiHelperIssueFormAids.entryFor(dom.overlay)).toBeUndefined();
    // The published global reference does not outlive the destroyed completion (R-005)
    expect(window.aiHelperInstances.autoCompletion).toBeUndefined();
  });

  it("attach destroys the completion and rethrows when init() itself fails halfway (CRF-098)", async () => {
    await loadModule();
    const dom = buildIssueForm({ persisted: false });
    autoCompletion.Mock.prototype.init = function() { throw new Error("init boom"); };

    expect(() => window.AiHelperIssueFormAids.attach(dom.overlay)).toThrow("init boom");

    expect(autoCompletion.instances[0].destroy).toHaveBeenCalled();
    expect(window.AiHelperIssueFormAids.entryFor(dom.overlay)).toBeUndefined();
  });

  it("attach reports both errors when releasing the half-built parts fails too", async () => {
    await loadModule();
    const dom = buildIssueForm({ persisted: false });
    vi.stubGlobal("AiHelperTypoChecker", { initFromConfig: vi.fn(() => { throw new Error("typo boom"); }) });
    // The completion created by this attach fails to destroy
    const Failing = function(textarea, options) {
      this.textarea = textarea;
      this.options = options;
      this.init = vi.fn();
      this.destroy = vi.fn(() => { throw new Error("destroy boom"); });
    };
    vi.stubGlobal("AiHelperAutoCompletion", Failing);

    let thrown;
    try {
      window.AiHelperIssueFormAids.attach(dom.overlay);
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(AggregateError);
    expect(thrown.errors.map((e) => e.message)).toEqual(["typo boom", "destroy boom"]);
    expect(window.AiHelperIssueFormAids.entryFor(dom.overlay)).toBeUndefined();
  });

  it("a failed attach leaves no live duplicate-check listener behind (CRF-098)", async () => {
    await loadModule();
    const dom = buildIssueForm({ persisted: false });
    const Failing = function(options) {
      this.init = vi.fn(() => { throw new Error("suggestion boom"); });
      this.destroy = vi.fn();
      this.options = options;
    };
    vi.stubGlobal("AiHelperAssignmentSuggestion", Failing);
    const fetchStub = installFetchStub();

    expect(() => window.AiHelperIssueFormAids.attach(dom.overlay)).toThrow("suggestion boom");
    dom.subject.value = "subject";
    dom.duplicate.button.click();

    // The released render's button must not start a request nobody can abort
    expect(fetchStub.calls).toHaveLength(0);
  });

  it("scan lets the attach error surface and records the container so it is not retried", async () => {
    const typoStub = { initFromConfig: vi.fn(() => { throw new Error("typo boom"); }) };
    vi.stubGlobal("AiHelperTypoChecker", typoStub);
    await loadModule();
    const dom = buildIssueForm({ persisted: false });

    expect(() => window.AiHelperIssueFormAids.scan(document)).toThrow("typo boom");
    // The failed container is skipped from then on
    expect(() => window.AiHelperIssueFormAids.scan(document)).not.toThrow();

    expect(typoStub.initFromConfig).toHaveBeenCalledTimes(1);
    expect(window.AiHelperIssueFormAids.entryFor(dom.overlay)).toBeUndefined();
    expect(autoCompletion.instances).toHaveLength(1);
    // No half-built completion was left behind
    expect(autoCompletion.instances[0].destroy).toHaveBeenCalled();
    // No fallback: nothing is swallowed into console.error
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it("start() rethrows a failing description attach but still attaches the notes aids and observes the form", async () => {
    await loadModule();
    buildIssueForm({ persisted: true });
    const initFromConfig = vi.fn((overlay, textareaId) => {
      if (textareaId === "issue_description") {
        throw new Error("typo boom");
      }
      return null;
    });
    vi.stubGlobal("AiHelperTypoChecker", { initFromConfig });

    expect(() => window.AiHelperIssueFormAids.start()).toThrow("typo boom");

    // Notes aids are independent of the failed description render
    expect(window.aiHelperInstances.notesAutoCompletion).toBeDefined();
    // The observer is running: the next render is attached
    initFromConfig.mockImplementation(() => null);
    const nextRender = rerenderAllAttributes({ persisted: true, hookOutput: true });
    await flushPromises();
    expect(window.AiHelperIssueFormAids.entryFor(nextRender.overlay)).toBeDefined();
  });

  it("an attach error in the observer callback surfaces as an uncaught error, once per render, and a fresh render is retried", async () => {
    await loadModule();
    buildIssueForm({ persisted: false });
    const typoStub = { initFromConfig: vi.fn(() => { throw new Error("typo boom"); }) };
    window.AiHelperIssueFormAids.start();

    vi.stubGlobal("AiHelperTypoChecker", typoStub);
    rerenderAllAttributes({ persisted: false, hookOutput: true });
    await flushPromises();
    expect(windowErrors.map((e) => e.message)).toEqual(["typo boom"]);

    // Another mutation of the same render neither retries nor reports again
    document.getElementById("all_attributes").appendChild(document.createElement("div"));
    await flushPromises();
    expect(windowErrors).toHaveLength(1);
    expect(typoStub.initFromConfig).toHaveBeenCalledTimes(1);

    // A fresh render is attached again
    typoStub.initFromConfig.mockImplementation(() => null);
    const fresh = rerenderAllAttributes({ persisted: false, hookOutput: true });
    await flushPromises();
    expect(window.AiHelperIssueFormAids.entryFor(fresh.overlay)).toBeDefined();
    expect(windowErrors).toHaveLength(1);
  });

  it("a release that throws surfaces once, drops the registration and does not keep the new render from attaching", async () => {
    const dom = buildIssueForm({ persisted: false });
    await loadModule();
    window.AiHelperIssueFormAids.start();
    const firstEntry = window.AiHelperIssueFormAids.entryFor(dom.overlay);
    firstEntry.autoCompletion.destroy = vi.fn(() => { throw new Error("destroy boom"); });

    const secondRender = rerenderAllAttributes({ persisted: false, hookOutput: true });
    await flushPromises();

    expect(windowErrors.map((e) => e.message)).toEqual(["destroy boom"]);
    expect(window.AiHelperIssueFormAids.entryFor(dom.overlay)).toBeUndefined();
    expect(window.AiHelperIssueFormAids.entryFor(secondRender.overlay)).toBeDefined();

    // Later mutations must not destroy the same entry again
    rerenderAllAttributes({ persisted: false, hookOutput: true });
    await flushPromises();
    expect(firstEntry.autoCompletion.destroy).toHaveBeenCalledTimes(1);
    expect(windowErrors).toHaveLength(1);
  });

  it("attach throws when the render has no data-config (boundary input is not defaulted)", async () => {
    await loadModule();
    const dom = buildIssueForm({ persisted: false });
    delete dom.overlay.dataset.config;

    expect(() => window.AiHelperIssueFormAids.attach(dom.overlay)).toThrow("data-config");
    expect(autoCompletion.instances).toHaveLength(0);
  });

  it("attach throws when the render has an assignee select but no data-assignment-config", async () => {
    await loadModule();
    const dom = buildIssueForm({ persisted: false });
    delete dom.overlay.dataset.assignmentConfig;

    expect(() => window.AiHelperIssueFormAids.attach(dom.overlay)).toThrow("data-assignment-config");
    expect(assignmentSuggestion.instances).toHaveLength(0);
    // The completion created before the failing step was released again
    expect(autoCompletion.instances[0].destroy).toHaveBeenCalled();
  });

  it("a second click on the duplicate check aborts the first request and only the second result is shown", async () => {
    const dom = buildIssueForm({ persisted: false });
    await loadModule();
    const fetchStub = installFetchStub();
    window.AiHelperIssueFormAids.start();
    dom.subject.value = "subject";

    dom.duplicate.button.click();
    dom.duplicate.button.click();
    expect(fetchStub.calls).toHaveLength(2);
    expect(fetchStub.calls[0].options.signal.aborted).toBe(true);
    expect(fetchStub.calls[1].options.signal.aborted).toBe(false);

    fetchStub.calls[0].resolve({ html: "<div>first</div>" });
    await flushPromises();
    expect(dom.duplicate.results.innerHTML).toBe("");

    fetchStub.calls[1].resolve({ html: "<div>second</div>" });
    await flushPromises();
    expect(dom.duplicate.results.innerHTML).toBe("<div>second</div>");
    expect(dom.duplicate.loading.style.display).toBe("none");
    expect(errorSpy).not.toHaveBeenCalled();
  });

  // --- Notes-field aids (US2, R-004): created once at page display,
  // outside the per-render registry ---

  it("attachNotes creates the notes completion and notes typo checker once for a persisted issue (US2)", async () => {
    const dom = buildIssueForm({ persisted: true });
    await loadModule();

    window.AiHelperIssueFormAids.start();

    const notesCompletion = window.aiHelperInstances.notesAutoCompletion;
    expect(notesCompletion).toBeDefined();
    expect(notesCompletion.textarea.id).toBe("issue_notes");
    // The notes aids are not part of the per-render entry
    const entry = window.AiHelperIssueFormAids.entryFor(dom.overlay);
    expect(entry.notesAutoCompletion).toBeUndefined();
    // The notes typo checker ran on the notes textarea
    expect(dom.notes.textarea.classList.contains("ai-helper-textarea-positioned")).toBe(true);

    // A second start() does not recreate them
    window.AiHelperIssueFormAids.start();
    expect(window.aiHelperInstances.notesAutoCompletion).toBe(notesCompletion);
    // One description completion + one notes completion, no duplicates
    expect(autoCompletion.instances.length).toBe(2);
  });

  it("attachNotes creates nothing when isPersistedIssue is false even with a notes textarea", async () => {
    // Synthetic combination exercising the isPersistedIssue guard
    const dom = buildIssueForm({ persisted: false });
    const notes = createJstEditor("issue_notes");
    dom.form.querySelector("fieldset#add_notes")?.remove();
    const addNotes = document.createElement("fieldset");
    addNotes.id = "add_notes";
    addNotes.appendChild(notes.block);
    dom.form.appendChild(addNotes);
    await loadModule();

    window.AiHelperIssueFormAids.start();

    expect(window.aiHelperInstances.notesAutoCompletion).toBeUndefined();
    expect(notes.textarea.classList.contains("ai-helper-textarea-positioned")).toBe(false);
  });

  it("attachNotes creates nothing when the page has no notes textarea", async () => {
    // An edit form whose user may edit attributes but not add notes renders
    // no fieldset#add_notes at all, so there is no #issue_notes
    const dom = buildIssueForm({ persisted: true });
    dom.addNotes.remove();
    await loadModule();

    window.AiHelperIssueFormAids.start();

    expect(window.aiHelperInstances.notesAutoCompletion).toBeUndefined();
  });

  it("after a re-render the notes aids survive untouched and the notes containers stay unique (US2)", async () => {
    buildIssueForm({ persisted: true });
    await loadModule();
    window.AiHelperIssueFormAids.start();
    const notesCompletion = window.aiHelperInstances.notesAutoCompletion;

    rerenderAllAttributes({ persisted: true, hookOutput: true });
    await flushPromises();

    expect(window.aiHelperInstances.notesAutoCompletion).toBe(notesCompletion);
    expect(document.querySelectorAll("#ai-helper-notes-checkbox-container").length).toBe(1);
    expect(document.querySelectorAll("#ai-helper-typo-control-panel-notes").length).toBe(1);
    expect(document.querySelectorAll("#ai-helper-typo-check-notes-btn").length).toBe(1);
  });

  it("a re-render changes neither the notes content nor the completion toggle (US2-4)", async () => {
    const dom = buildIssueForm({ persisted: true });
    await loadModule();
    window.AiHelperIssueFormAids.start();
    const notesCompletion = window.aiHelperInstances.notesAutoCompletion;
    dom.notes.textarea.value = "draft note text";
    const notesToggle = document.getElementById("ai-helper-autocompletion-notes-toggle");
    notesToggle.checked = true;
    notesToggle.dispatchEvent(new Event("change", { bubbles: true }));

    rerenderAllAttributes({ persisted: true, hookOutput: true });
    await flushPromises();

    expect(document.getElementById("issue_notes").value).toBe("draft note text");
    expect(document.getElementById("ai-helper-autocompletion-notes-toggle").checked).toBe(true);
    expect(window.aiHelperInstances.notesAutoCompletion).toBe(notesCompletion);
    expect(notesCompletion.destroy).not.toHaveBeenCalled();
  });

  it("after a re-render the description completion, typo checker and assignment suggestion are re-attached (US2)", async () => {
    const dom = buildIssueForm({ persisted: true });
    await loadModule();
    window.AiHelperIssueFormAids.start();
    const firstEntry = window.AiHelperIssueFormAids.entryFor(dom.overlay);
    const notesCompletion = window.aiHelperInstances.notesAutoCompletion;

    const secondRender = rerenderAllAttributes({ persisted: true, hookOutput: true });
    await flushPromises();

    const secondEntry = window.AiHelperIssueFormAids.entryFor(secondRender.overlay);
    expect(secondEntry.autoCompletion).toBeDefined();
    expect(secondEntry.autoCompletion).not.toBe(firstEntry.autoCompletion);
    expect(secondEntry.typoChecker).not.toBeNull();
    expect(secondEntry.typoChecker.textarea.id).toBe("issue_description");
    expect(secondEntry.assignmentSuggestion).toBeDefined();
    expect(firstEntry.autoCompletion.destroy).toHaveBeenCalled();
    // The notes completion is untouched by the release
    expect(window.aiHelperInstances.notesAutoCompletion).toBe(notesCompletion);
    expect(notesCompletion.destroy).not.toHaveBeenCalled();
  });

  it("a render without a description textarea (not editable by the user) attaches null completion and typo checker without failing", async () => {
    buildIssueForm({ persisted: true });
    await loadModule();
    window.AiHelperIssueFormAids.start();

    const secondRender = rerenderAllAttributes({ persisted: true, hookOutput: true, withDescription: false });
    await flushPromises();

    const secondEntry = window.AiHelperIssueFormAids.entryFor(secondRender.overlay);
    expect(secondEntry).toBeDefined();
    expect(secondEntry.autoCompletion).toBeNull();
    expect(secondEntry.typoChecker).toBeNull();
    expect(errorSpy).not.toHaveBeenCalled();
    // The notes aids are unaffected
    expect(window.aiHelperInstances.notesAutoCompletion).toBeDefined();
  });

  it("attachNotes throws when a persisted issue's notes editor has no notes controls", async () => {
    await loadModule();
    buildIssueForm({ persisted: true, notesControls: false });

    expect(() => window.AiHelperIssueFormAids.start()).toThrow("ai-helper-notes-checkbox-container");
  });

  it("a re-render of an edit form whose description editor is still hidden keeps the checkbox inside the hidden wrapper", async () => {
    // issues/_form.html.erb renders the editor of a persisted issue inside a
    // display:none span until the edit link is clicked; the textarea exists
    buildIssueForm({ persisted: true, descriptionHidden: true });
    await loadModule();
    window.AiHelperIssueFormAids.start();

    const secondRender = rerenderAllAttributes({ persisted: true, hookOutput: true, descriptionHidden: true });
    await flushPromises();

    const entry = window.AiHelperIssueFormAids.entryFor(secondRender.overlay);
    expect(entry.autoCompletion).not.toBeNull();
    expect(secondRender.descControls.container.parentNode).toBe(secondRender.wrapper);
    expect(secondRender.wrapper.style.display).toBe("none");
    expect(secondRender.desc.block.nextElementSibling).toBe(secondRender.descControls.container);
  });

  // --- Project switch (US3, FR-005, SC-003) ---

  it("switching to a project with the module disabled releases every registration and clears the global reference (SC-003)", async () => {
    const dom = buildIssueForm({ persisted: false });
    await loadModule();
    window.AiHelperIssueFormAids.start();
    const firstEntry = window.AiHelperIssueFormAids.entryFor(dom.overlay);
    const firstCompletion = window.aiHelperInstances.autoCompletion;

    // The re-render for a project with the module disabled renders no hook output
    rerenderAllAttributes({ persisted: false, hookOutput: false });
    await flushPromises();

    expect(firstEntry.autoCompletion.destroy).toHaveBeenCalled();
    expect(firstEntry.typoChecker.destroyed).toBe(true);
    expect(firstEntry.assignmentSuggestion.destroy).toHaveBeenCalled();
    expect(window.AiHelperIssueFormAids.entryFor(dom.overlay)).toBeUndefined();
    expect(window.aiHelperInstances.autoCompletion).toBeUndefined();
    expect(window.aiHelperInstances.autoCompletion).not.toBe(firstCompletion);
  });

  it("switching back to an enabled project re-attaches the aids", async () => {
    buildIssueForm({ persisted: false });
    await loadModule();
    window.AiHelperIssueFormAids.start();

    rerenderAllAttributes({ persisted: false, hookOutput: false });
    await flushPromises();
    const reEnabled = rerenderAllAttributes({ persisted: false, hookOutput: true });
    await flushPromises();

    const entry = window.AiHelperIssueFormAids.entryFor(reEnabled.overlay);
    expect(entry).toBeDefined();
    expect(entry.autoCompletion).toBe(autoCompletion.instances.at(-1));
    expect(window.aiHelperInstances.autoCompletion).toBe(entry.autoCompletion);
  });

  it("a switch between two enabled projects reads the new render's configs, not the previous project's endpoints", async () => {
    buildIssueForm({ persisted: false });
    await loadModule();
    window.AiHelperIssueFormAids.start();

    // Re-render as project 3 (buildFormDetails renders /projects/3 endpoints
    // only via overrides, so swap the config of the fresh render manually)
    const secondRender = rerenderAllAttributes({ persisted: false, hookOutput: true });
    secondRender.overlay.dataset.config = createConfig({
      descriptionEndpoint: "/projects/3/ai_helper/issue/new/suggest_completion",
      projectId: "3",
      duplicateCheckEndpoint: "/projects/3/ai_helper/check_duplicates",
    });
    secondRender.overlay.dataset.assignmentConfig = createAssignmentConfig({
      endpoint: "/projects/3/ai_helper/issue/new/suggest_assignees",
    });
    await flushPromises();

    const entry = window.AiHelperIssueFormAids.entryFor(secondRender.overlay);
    expect(entry.autoCompletion.options.endpoint).toBe("/projects/3/ai_helper/issue/new/suggest_completion");
    expect(entry.assignmentSuggestion.options.endpoint).toBe("/projects/3/ai_helper/issue/new/suggest_assignees");

    document.getElementById("issue_description").value = "text";
    document.getElementById("issue_subject").value = "subject";
    const fetchStub = installFetchStub();
    document.getElementById("ai-helper-duplicate-check-btn").click();
    expect(fetchStub.calls[0].url).toBe("/projects/3/ai_helper/check_duplicates");
  });

  // Assumption: a page opened ON a project with the module disabled does not
  // load this script at all (_html_header.html.erb renders the script tags
  // only when the module is enabled), so switching to an enabled project
  // needs a full page reload — there is nothing to attach with. Out of scope
  // (US3-4, FR-005).

  // --- Completion on/off carry-over (FR-006, R-006) ---

  it("a completion enabled before the re-render starts enabled on the new instance (FR-006)", async () => {
    localStorage.setItem("aiHelperAutoCompletion_1", JSON.stringify({ enabled: true }));
    const dom = buildIssueForm({ persisted: false });
    await loadScript("assets/javascripts/autocompletion/ai_helper_auto_completion");
    await loadScript("assets/javascripts/autocompletion/ai_helper_auto_completion_overlay");
    await loadModule();
    vi.restoreAllMocks();
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    window.AiHelperIssueFormAids.start();
    const firstEntry = window.AiHelperIssueFormAids.entryFor(dom.overlay);
    expect(firstEntry.autoCompletion.isEnabled).toBe(true);

    rerenderAllAttributes({ persisted: false, hookOutput: true });
    await flushPromises();

    const secondEntry = window.AiHelperIssueFormAids.entryFor(
      document.getElementById("ai-helper-issue-textarea-overlay")
    );
    expect(secondEntry.autoCompletion.isEnabled).toBe(true);
    expect(secondEntry.autoCompletion).not.toBe(firstEntry.autoCompletion);
  });

  // --- Five consecutive re-renders (SC-002) ---

  it("survives five consecutive re-renders with one set of controls and a single typo-check request (SC-002)", async () => {
    buildIssueForm({ persisted: false });
    await loadScript("assets/javascripts/typo_checker/ai_helper_typo_checker");
    await loadScript("assets/javascripts/autocompletion/ai_helper_assignment_suggestion");
    await loadModule();
    const fetchStub = installFetchStub();
    vi.restoreAllMocks();
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    window.AiHelperIssueFormAids.start();

    for (let i = 0; i < 5; i++) {
      rerenderAllAttributes({ persisted: false, hookOutput: true });
      await flushPromises();
    }

    expect(document.querySelectorAll("#ai-helper-description-checkbox-container").length).toBe(1);
    expect(document.querySelectorAll("#ai-helper-typo-check-description-btn").length).toBe(1);
    expect(document.querySelectorAll("#ai-helper-duplicate-check-btn").length).toBe(1);
    expect(document.querySelectorAll(".ai-helper-suggest-assignee-link").length).toBe(1);

    document.getElementById("issue_description").value = "some text to check";
    document.getElementById("ai-helper-typo-check-description-btn").click();
    await flushPromises();
    expect(fetchStub.calls.length).toBe(1);
  });
});
