import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";
import { createJstEditor } from "../support/jst_editor.js";

/**
 * Builds the DOM that Redmine + the ai_helper journal-edit partial render.
 *
 * Transcribed from the production markup (CRF-042):
 * - issues/show renders `#history` with `div#change-<id>` per journal; the
 *   displayed notes sit in `#journal-<id>-notes` (journals/edit.js.erb hides
 *   this and inserts the form after it, making the form a sibling).
 * - journals/_notes_form.html.erb renders `form#journal-<id>-form` inside
 *   `#change-<id>` with the `journal_<id>_notes` textarea wrapped by
 *   wikitoolbar_for into a `.jstBlock`, the private-notes checkbox, then the
 *   view_journals_notes_form_after_notes hook output: the
 *   `.ai-helper-journal-edit-controls` container (hidden), then the
 *   submit/cancel paragraph.
 *
 * @param {number} journalId - The journal id the form edits.
 */
function createJournalHistoryDOM(journalId = 42) {
  const history = document.createElement("div");
  history.id = "history";
  document.body.appendChild(history);

  const change = document.createElement("div");
  change.id = `change-${journalId}`;
  history.appendChild(change);

  const notesDisplay = document.createElement("div");
  notesDisplay.id = `journal-${journalId}-notes`;
  change.appendChild(notesDisplay);

  const form = document.createElement("form");
  form.id = `journal-${journalId}-form`;
  form.setAttribute("action", `/journals/${journalId}`);
  change.appendChild(form);

  const { block, textarea } = createJstEditor(`journal_${journalId}_notes`);
  form.appendChild(block);

  const controls = buildControls(journalId);
  form.appendChild(controls);

  const paragraph = document.createElement("p");
  const submit = document.createElement("button");
  submit.type = "submit";
  paragraph.appendChild(submit);
  form.appendChild(paragraph);

  return { history, change, form, textarea, controls };
}

/** Typo labels matching the shared TypoCheckLabels keys. */
function typoLabels() {
  return {
    suggestionsTitle: "Suggestions",
    noSuggestions: "No typos found",
    checkButton: "Check",
    checking: "Checking...",
    acceptSuggestion: "Accept",
    dismissSuggestion: "Reject",
    acceptAll: "Accept all",
    dismissAll: "Reject all",
    errorOccurred: "An error occurred",
    correctionTooltip: "Suggested correction",
    applyFailed: "Failed to apply",
  };
}

/**
 * Builds the `.ai-helper-journal-edit-controls` container exactly as
 * app/views/ai_helper/journals/_notes_form_controls.html.erb renders it.
 * @param {number} journalId - The journal id.
 */
function buildControls(journalId) {
  const controls = document.createElement("div");
  controls.className = "ai-helper-journal-edit-controls ai-helper-autocompletion-controls";
  controls.style.display = "none";
  controls.dataset.config = JSON.stringify({
    journalId: journalId,
    textareaId: `journal_${journalId}_notes`,
    completionEndpoint: `/projects/1/ai_helper/issue/${journalId}/suggest_completion`,
    typoEndpoint: "/projects/1/ai_helper/check_typos",
    userId: 7,
    debounceDelay: 500,
    minLength: 5,
    suggestionColor: "#888888",
    completionLabels: {
      commonToggleLabel: "AI Completion",
      loading: "Loading...",
      noSuggestions: "No suggestions",
      acceptSuggestion: "Accept suggestion",
      dismiss: "Dismiss",
      enabledTooltip: "note enabled",
      disabledTooltip: "note disabled",
      noteEnabledTooltip: "note enabled",
      noteDisabledTooltip: "note disabled",
    },
    typoLabels: typoLabels(),
  });

  const row = document.createElement("div");
  const span = document.createElement("span");
  const checkbox = document.createElement("input");
  checkbox.type = "checkbox";
  checkbox.id = `ai-helper-journal-${journalId}-autocompletion-toggle`;
  checkbox.className = "ai-helper-journal-autocompletion-toggle";
  const label = document.createElement("label");
  label.setAttribute("for", checkbox.id);
  span.appendChild(checkbox);
  span.appendChild(label);
  row.appendChild(span);

  const checkButton = document.createElement("a");
  checkButton.className = "icon icon-edit ai-helper-journal-typo-check-btn";
  checkButton.innerHTML = '<svg></svg> Check';
  row.appendChild(checkButton);
  controls.appendChild(row);

  const panel = document.createElement("div");
  panel.className = "ai-helper-typo-control-panel ai-helper-journal-typo-control-panel";
  panel.style.display = "none";
  const applyAll = document.createElement("button");
  applyAll.type = "button";
  applyAll.className = "ai-helper-typo-apply-all-btn";
  const close = document.createElement("button");
  close.type = "button";
  close.className = "ai-helper-typo-close-btn";
  panel.appendChild(applyAll);
  panel.appendChild(close);
  controls.appendChild(panel);

  const templates = document.createElement("div");
  templates.style.display = "none";
  const acceptTemplate = document.createElement("button");
  acceptTemplate.type = "button";
  acceptTemplate.className = "ai-helper-typo-accept-btn-template";
  const rejectTemplate = document.createElement("button");
  rejectTemplate.type = "button";
  rejectTemplate.className = "ai-helper-typo-reject-btn-template";
  templates.appendChild(acceptTemplate);
  templates.appendChild(rejectTemplate);
  controls.appendChild(templates);

  return controls;
}

/** Lets the MutationObserver callback (a microtask) run. */
function flushMicrotasks() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("AiHelperJournalEditAids", () => {
  let dom;

  beforeEach(async () => {
    await loadScript("assets/javascripts/shared/ai_helper_editor_controls");
    await loadScript("assets/javascripts/autocompletion/ai_helper_auto_completion");
    // Loaded by _html_header.html.erb right after the completion class
    await loadScript("assets/javascripts/autocompletion/ai_helper_auto_completion_overlay");
    await loadScript("assets/javascripts/typo_checker/ai_helper_typo_checker");
    await loadScript("assets/javascripts/typo_checker/ai_helper_typo_suggestion_overlay");
    await loadScript("assets/javascripts/autocompletion/ai_helper_journal_edit_aids");
    // The accept/reject button templates are looked up document-wide by the
    // overlay renderer; the partial renders its own copy inside the container.
  });

  afterEach(() => {
    document.body.innerHTML = "";
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  describe("attach", () => {
    it("attaches a typo checker bound to the form's own button/panel and places the container after the editor", () => {
      dom = createJournalHistoryDOM(42);
      const block = dom.form.querySelector(".jstBlock");

      // Precondition (CRF-042/CRF-077): the fixture renders the container
      // where the production hook does — inside the form, after the .jstBlock,
      // before the submit paragraph — and still hidden
      expect(dom.controls.parentNode).toBe(dom.form);
      expect(block.nextSibling).toBe(dom.controls);
      expect(dom.controls.nextSibling.tagName).toBe("P");
      expect(dom.controls.style.display).toBe("none");

      // Captured before attach: the typo checker relocates the control panel
      // under the textarea's parent when initialized
      const checkButton = dom.controls.querySelector(".ai-helper-journal-typo-check-btn");
      const controlPanel = dom.controls.querySelector(".ai-helper-journal-typo-control-panel");

      const placeSpy = vi.spyOn(window.AiHelperEditorControls, "placeAfterEditor");
      const entry = window.AiHelperJournalEditAids.attach(dom.controls);

      expect(placeSpy).toHaveBeenCalledWith(dom.textarea, dom.controls);

      expect(entry).not.toBeNull();
      expect(entry.typoChecker).toBeInstanceOf(window.AiHelperTypoChecker);
      expect(entry.typoChecker.textarea).toBe(dom.textarea);
      expect(entry.typoChecker.checkButton).toBe(checkButton);
      expect(entry.typoChecker.controlPanel).toBe(controlPanel);
      expect(entry.typoChecker.options.endpoint).toBe("/projects/1/ai_helper/check_typos");
      expect(entry.typoChecker.options.labels.suggestionsTitle).toBe("Suggestions");

      // The container was moved after the .jstBlock and revealed
      expect(dom.controls.parentNode).toBe(dom.form);
      expect(block.nextSibling).toBe(dom.controls);
      expect(dom.controls.style.display).toBe("block");
    });

    it("does not attach twice for the same form", () => {
      dom = createJournalHistoryDOM(42);

      const first = window.AiHelperJournalEditAids.attach(dom.controls);
      const second = window.AiHelperJournalEditAids.attach(dom.controls);

      expect(second).toBe(first);
      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).toBe(first);
    });

    it("throws on invalid data-config JSON", () => {
      dom = createJournalHistoryDOM(42);
      dom.controls.dataset.config = "{not json";

      expect(() => window.AiHelperJournalEditAids.attach(dom.controls)).toThrow();
      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).toBeUndefined();
    });

    it("throws when the configured textarea is not inside the form", () => {
      dom = createJournalHistoryDOM(42);
      const config = JSON.parse(dom.controls.dataset.config);
      config.textareaId = "issue_notes";
      dom.controls.dataset.config = JSON.stringify(config);

      expect(() => window.AiHelperJournalEditAids.attach(dom.controls))
        .toThrow(/textarea #issue_notes not found/);
      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).toBeUndefined();
    });
  });

  describe("scan", () => {
    it("attaches all containers within the root", () => {
      dom = createJournalHistoryDOM(42);
      const second = createJournalHistoryDOM(43);

      window.AiHelperJournalEditAids.scan(document.body);

      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).not.toBeUndefined();
      expect(window.AiHelperJournalEditAids.entryFor(second.form)).not.toBeUndefined();
      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).not.toBe(
        window.AiHelperJournalEditAids.entryFor(second.form)
      );
    });
  });

  describe("start", () => {
    it("does nothing when #history is absent", () => {
      const orphan = buildControls(44);
      const host = document.createElement("div");
      host.id = "not-history";
      host.appendChild(orphan);
      document.body.appendChild(host);

      expect(() => window.AiHelperJournalEditAids.start()).not.toThrow();
      expect(orphan.style.display).toBe("none");
    });

    it("scans existing containers and attaches forms inserted later", async () => {
      dom = createJournalHistoryDOM(42);

      window.AiHelperJournalEditAids.start();
      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).not.toBeUndefined();

      const later = createJournalHistoryDOM(43);
      document.body.appendChild(later.history);
      dom.history.appendChild(later.change);

      await flushMicrotasks();

      expect(window.AiHelperJournalEditAids.entryFor(later.form)).not.toBeUndefined();
      // The pre-existing form keeps its original registration
      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).not.toBe(
        window.AiHelperJournalEditAids.entryFor(later.form)
      );
    });
  });
});

describe("AiHelperJournalEditAids end-to-end typo check (US1)", () => {
  let dom;

  beforeEach(async () => {
    await loadScript("assets/javascripts/shared/ai_helper_editor_controls");
    await loadScript("assets/javascripts/autocompletion/ai_helper_auto_completion");
    // Loaded by _html_header.html.erb right after the completion class
    await loadScript("assets/javascripts/autocompletion/ai_helper_auto_completion_overlay");
    await loadScript("assets/javascripts/typo_checker/ai_helper_typo_checker");
    await loadScript("assets/javascripts/typo_checker/ai_helper_typo_suggestion_overlay");
    await loadScript("assets/javascripts/autocompletion/ai_helper_journal_edit_aids");
  });

  afterEach(() => {
    document.body.innerHTML = "";
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("clicking the form's check button fetches the typo endpoint with only that form's text, shows the overlay, and accepting changes only that textarea", async () => {
    dom = createJournalHistoryDOM(42);
    const entry = window.AiHelperJournalEditAids.attach(dom.controls);

    // A second textarea standing in for the new-comment field
    const newCommentTextarea = document.createElement("textarea");
    newCommentTextarea.id = "issue_notes";
    newCommentTextarea.value = "The new comment draft stays untouched";
    document.body.appendChild(newCommentTextarea);

    dom.textarea.value = "This sentence contains a mispelled word.";

    const fetchCalls = [];
    vi.stubGlobal("fetch", vi.fn((url, options) => {
      fetchCalls.push({ url, options });
      return Promise.resolve({
        ok: true,
        status: 200,
        json: () => Promise.resolve({
          suggestions: [{ original: "mispelled", corrected: "misspelled", position: 24 }],
        }),
      });
    }));

    dom.controls.querySelector(".ai-helper-journal-typo-check-btn").dispatchEvent(new Event("click", { bubbles: true }));
    await new Promise((resolve) => setTimeout(resolve, 20));

    expect(fetchCalls).toHaveLength(1);
    expect(fetchCalls[0].url).toBe("/projects/1/ai_helper/check_typos");
    expect(JSON.parse(fetchCalls[0].options.body)).toEqual({
      text: "This sentence contains a mispelled word.",
    });

    expect(entry.typoChecker.overlay.classList.contains("ai-helper-typo-overlay-active")).toBe(true);

    entry.typoChecker.overlay.querySelector(".ai-helper-typo-accept-btn").click();
    await new Promise((resolve) => setTimeout(resolve, 10));

    expect(dom.textarea.value).toContain("misspelled");
    expect(dom.textarea.value).not.toContain("mispelled");
    expect(newCommentTextarea.value).toBe("The new comment draft stays untouched");
  });
});

describe("AiHelperJournalEditAids auto-completion attachment (085 US2)", () => {
  beforeEach(async () => {
    localStorage.clear();
  });

  afterEach(() => {
    document.body.innerHTML = "";
    localStorage.clear();
    vi.restoreAllMocks();
  });

  it("creates an auto completion for the form and passes it to the typo checker", () => {
    const dom = createJournalHistoryDOM(42);

    const entry = window.AiHelperJournalEditAids.attach(dom.controls);

    expect(entry.autoCompletion).toBeInstanceOf(window.AiHelperAutoCompletion);
    expect(entry.autoCompletion.textarea).toBe(dom.textarea);
    expect(entry.autoCompletion.options.contextType).toBe("note");
    expect(entry.autoCompletion.options.endpoint).toBe("/projects/1/ai_helper/issue/42/suggest_completion");
    expect(entry.autoCompletion.options.journalId).toBe(42);
    expect(entry.autoCompletion.options.userId).toBe(7);
    expect(entry.autoCompletion.options.labels.enabledTooltip).toBe("note enabled");
    expect(entry.autoCompletion.checkbox).toBe(dom.controls.querySelector(".ai-helper-journal-autocompletion-toggle"));
    expect(entry.autoCompletion.container).toBe(dom.controls);
    // The typo checker pauses exactly this instance while the overlay is shown
    expect(entry.typoChecker.options.autoCompletion).toBe(entry.autoCompletion);
  });

  it("checkbox initial state reads the shared localStorage key and toggling writes it (R-009)", () => {
    const dom = createJournalHistoryDOM(42);
    localStorage.setItem("aiHelperAutoCompletion_7", JSON.stringify({ enabled: true }));

    const entry = window.AiHelperJournalEditAids.attach(dom.controls);

    const checkbox = entry.autoCompletion.checkbox;
    expect(checkbox.checked).toBe(true);

    // Toggling the edit-form checkbox writes the same shared key
    checkbox.checked = false;
    checkbox.dispatchEvent(new Event("change"));
    expect(JSON.parse(localStorage.getItem("aiHelperAutoCompletion_7")).enabled).toBe(false);
  });
});

describe("AiHelperJournalEditAids multi-form lifecycle (085 US3)", () => {
  beforeEach(async () => {
    localStorage.clear();
  });

  afterEach(() => {
    document.body.innerHTML = "";
    localStorage.clear();
    vi.restoreAllMocks();
  });

  it("registers two forms independently and a typo check in form A leaves form B and the new-comment field unchanged", async () => {
    const a = createJournalHistoryDOM(42);
    const b = createJournalHistoryDOM(43);

    const newComment = document.createElement("textarea");
    newComment.id = "issue_notes";
    newComment.value = "draft untouched by any form";
    document.body.appendChild(newComment);

    const entryA = window.AiHelperJournalEditAids.attach(a.controls);
    const entryB = window.AiHelperJournalEditAids.attach(b.controls);
    expect(entryA).not.toBe(entryB);

    const fetchCalls = [];
    vi.stubGlobal("fetch", vi.fn((url, options) => {
      fetchCalls.push({ url, options });
      return Promise.resolve({
        ok: true,
        status: 200,
        json: () => Promise.resolve({
          suggestions: [{ original: "mispelled", corrected: "misspelled", position: 24 }],
        }),
      });
    }));

    a.textarea.value = "This sentence contains a mispelled word.";
    b.textarea.value = "Form B keeps its own text.";

    a.controls.querySelector(".ai-helper-journal-typo-check-btn").dispatchEvent(new Event("click", { bubbles: true }));
    await new Promise((resolve) => setTimeout(resolve, 20));

    expect(fetchCalls).toHaveLength(1);
    expect(JSON.parse(fetchCalls[0].options.body).text).toBe("This sentence contains a mispelled word.");

    entryA.typoChecker.overlay.querySelector(".ai-helper-typo-accept-btn").click();
    await new Promise((resolve) => setTimeout(resolve, 10));

    expect(a.textarea.value).toContain("misspelled");
    expect(b.textarea.value).toBe("Form B keeps its own text.");
    expect(newComment.value).toBe("draft untouched by any form");
    // The typo-check request carries only the form's own text
    expect(JSON.parse(fetchCalls[0].options.body)).toEqual({
      text: "This sentence contains a mispelled word.",
    });
  });

  it("attaching the same form again does not create new instances", () => {
    const dom = createJournalHistoryDOM(42);
    const first = window.AiHelperJournalEditAids.attach(dom.controls);

    // Redmine's edit.js.erb calls show() on an existing form: no new elements
    const second = window.AiHelperJournalEditAids.attach(dom.controls);

    expect(second).toBe(first);
    expect(window.AiHelperJournalEditAids.entryFor(dom.form).typoChecker).toBe(first.typoChecker);
    expect(window.AiHelperJournalEditAids.entryFor(dom.form).autoCompletion).toBe(first.autoCompletion);
    expect(document.querySelectorAll(".ai-helper-journal-typo-check-btn").length).toBe(1);
    expect(document.querySelectorAll(".ai-helper-journal-autocompletion-toggle").length).toBe(1);
  });

  it.each([
    ["cancel (form.remove())", (dom) => dom.form.remove()],
    ["save (form.remove())", (dom) => dom.form.remove()],
    ["ancestor #change-<id> removal", (dom) => dom.change.remove()],
  ])("releasing a form removed by %s destroys both instances and deletes the registration", (_label, remove) => {
    const dom = createJournalHistoryDOM(42);
    const entry = window.AiHelperJournalEditAids.attach(dom.controls);
    const typoDestroy = vi.spyOn(entry.typoChecker, "destroy");
    const completionDestroy = vi.spyOn(entry.autoCompletion, "destroy");

    remove(dom);
    window.AiHelperJournalEditAids.releaseDetached();

    expect(typoDestroy).toHaveBeenCalledTimes(1);
    expect(completionDestroy).toHaveBeenCalledTimes(1);
    expect(window.AiHelperJournalEditAids.entryFor(dom.form)).toBeUndefined();
  });

  it("a form reopened after cancel gets fresh instances and exactly one link and one checkbox", () => {
    const dom = createJournalHistoryDOM(42);
    const first = window.AiHelperJournalEditAids.attach(dom.controls);
    const firstTypo = first.typoChecker;

    dom.form.remove();
    window.AiHelperJournalEditAids.releaseDetached();

    // Redmine renders a brand-new form element with a fresh editor for the
    // reopened edit (journals/edit.js.erb inserts a new notes_form partial)
    const reopened = document.createElement("form");
    reopened.id = "journal-42-form";
    const fresh = createJstEditor("journal_42_notes");
    reopened.appendChild(fresh.block);
    const controls = buildControls(42);
    reopened.appendChild(controls);
    document.body.appendChild(reopened);
    expect(reopened.querySelector(".ai-helper-journal-typo-check-btn")).not.toBeNull();

    const entry = window.AiHelperJournalEditAids.attach(controls);

    expect(entry).not.toBe(first);
    expect(entry.typoChecker).not.toBe(firstTypo);
    expect(entry.typoChecker.textarea).toBe(fresh.textarea);
    expect(document.querySelectorAll(".ai-helper-journal-typo-check-btn").length).toBe(1);
    expect(document.querySelectorAll(".ai-helper-journal-autocompletion-toggle").length).toBe(1);
  });

  it("a typo overlay left by a removed form is gone from the document", () => {
    const dom = createJournalHistoryDOM(42);
    const entry = window.AiHelperJournalEditAids.attach(dom.controls);

    // The overlay lives inside the textarea's parent; it must not survive the form
    dom.form.remove();
    window.AiHelperJournalEditAids.releaseDetached();

    expect(document.querySelectorAll(".ai-helper-typo-overlay").length).toBe(0);
    expect(document.querySelectorAll(".ai-helper-typo-control-panel").length).toBe(0);
    expect(entry.typoChecker.overlay.isConnected).toBe(false);
  });
});
