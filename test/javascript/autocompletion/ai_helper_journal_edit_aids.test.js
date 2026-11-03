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

  // journals/_notes_form.html.erb renders the private-notes hidden field,
  // checkbox and label between the editor and the hook output
  const privateHidden = document.createElement("input");
  privateHidden.type = "hidden";
  privateHidden.name = "journal[private_notes]";
  privateHidden.value = "0";
  form.appendChild(privateHidden);
  const privateCheckbox = document.createElement("input");
  privateCheckbox.type = "checkbox";
  privateCheckbox.id = `journal_${journalId}_private_notes`;
  form.appendChild(privateCheckbox);
  const privateLabel = document.createElement("label");
  privateLabel.setAttribute("for", privateCheckbox.id);
  form.appendChild(privateLabel);

  // The hook output follows the private-notes label, i.e. NOT yet right after
  // the editor: attach() must move it there
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
      // where the production hook does — inside the form, after the
      // private-notes label, before the submit paragraph — still hidden and
      // NOT yet directly after the editor
      expect(dom.controls.parentNode).toBe(dom.form);
      expect(block.nextSibling).not.toBe(dom.controls);
      expect(dom.controls.previousSibling.tagName).toBe("LABEL");
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

      // The container was moved directly after the .jstBlock (before the
      // private-notes elements) and revealed
      expect(dom.controls.parentNode).toBe(dom.form);
      expect(block.nextSibling).toBe(dom.controls);
      expect(dom.controls.nextSibling.tagName).toBe("INPUT");
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

    it.each([
      [".ai-helper-journal-autocompletion-toggle"],
      [".ai-helper-journal-typo-check-btn"],
      [".ai-helper-journal-typo-control-panel"],
    ])("throws without creating anything when the %s element is missing", (selector) => {
      dom = createJournalHistoryDOM(42);
      dom.controls.querySelector(selector).remove();
      const overlaysBefore = document.querySelectorAll(".ai-helper-textarea-overlay").length;

      expect(() => window.AiHelperJournalEditAids.attach(dom.controls))
        .toThrow(new RegExp(selector.replace(/\./g, "\\.")));

      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).toBeUndefined();
      expect(document.querySelectorAll(".ai-helper-textarea-overlay").length).toBe(overlaysBefore);
      // The new-comment checkbox must never be picked up as a fallback
      expect(dom.controls.style.display).toBe("none");
    });

    it("destroys the completion instance and registers nothing when the typo checker fails to initialize", () => {
      dom = createJournalHistoryDOM(42);
      const completionDestroy = vi.spyOn(window.AiHelperAutoCompletion.prototype, "destroy");
      vi.spyOn(window.AiHelperTypoChecker.prototype, "init").mockImplementation(() => {
        throw new Error("typo init failed");
      });

      expect(() => window.AiHelperJournalEditAids.attach(dom.controls)).toThrow(/typo init failed/);

      expect(completionDestroy).toHaveBeenCalledTimes(1);
      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).toBeUndefined();
      expect(document.querySelectorAll(".ai-helper-textarea-overlay").length).toBe(0);
    });

    it("releases the completion overlay and listeners and registers nothing when completion initialization fails after the overlay is created", () => {
      dom = createJournalHistoryDOM(42);
      // Reproduces a malformed saved setting: loadSettings() runs last in init(),
      // after the overlay and listeners already exist
      vi.spyOn(window.AiHelperAutoCompletion.prototype, "loadSettings").mockImplementation(() => {
        throw new Error("completion init failed");
      });
      const completionDestroy = vi.spyOn(window.AiHelperAutoCompletion.prototype, "destroy");

      expect(() => window.AiHelperJournalEditAids.attach(dom.controls)).toThrow(/completion init failed/);

      expect(completionDestroy).toHaveBeenCalledTimes(1);
      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).toBeUndefined();
      expect(document.querySelectorAll(".ai-helper-textarea-overlay").length).toBe(0);
    });

    it("returns the registered entry without parsing the configuration again", () => {
      dom = createJournalHistoryDOM(42);
      const first = window.AiHelperJournalEditAids.attach(dom.controls);
      dom.controls.dataset.config = "{not json";

      expect(window.AiHelperJournalEditAids.attach(dom.controls)).toBe(first);
    });
  });

  describe("completion request from the edit form (top level)", () => {
    afterEach(() => {
      vi.useRealTimers();
      localStorage.clear();
    });

    it("typing into the edit textarea posts context_type note and the journal id to the form's completion endpoint", async () => {
      localStorage.clear();
      dom = createJournalHistoryDOM(42);
      window.AiHelperJournalEditAids.attach(dom.controls);
      const toggle = dom.controls.querySelector(".ai-helper-journal-autocompletion-toggle");
      toggle.checked = true;
      toggle.dispatchEvent(new Event("change", { bubbles: true }));

      const fetchCalls = [];
      vi.stubGlobal("fetch", vi.fn((url, options) => {
        fetchCalls.push({ url, options });
        return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({ suggestion: "" }) });
      }));

      vi.useFakeTimers();
      dom.textarea.value = "I have reviewed the issue";
      dom.textarea.setSelectionRange(dom.textarea.value.length, dom.textarea.value.length);
      dom.textarea.dispatchEvent(new Event("input", { bubbles: true }));
      await vi.advanceTimersByTimeAsync(600);

      expect(fetchCalls).toHaveLength(1);
      expect(fetchCalls[0].url).toBe("/projects/1/ai_helper/issue/42/suggest_completion");
      const body = JSON.parse(fetchCalls[0].options.body);
      expect(body.context_type).toBe("note");
      expect(body.journal_id).toBe(42);
      expect(body.text).toBe("I have reviewed the issue");
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

  describe("scan with a container as root", () => {
    it("attaches a controls container passed directly as the root", () => {
      dom = createJournalHistoryDOM(42);
      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).toBeUndefined();

      window.AiHelperJournalEditAids.scan(dom.controls);

      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).not.toBeUndefined();
    });
  });

  describe("start", () => {
    it("never keeps two observers when called twice", () => {
      dom = createJournalHistoryDOM(42);
      const instances = [];
      class FakeObserver {
        constructor() {
          this.disconnect = vi.fn();
          this.observe = vi.fn();
          instances.push(this);
        }
      }
      vi.stubGlobal("MutationObserver", FakeObserver);

      window.AiHelperJournalEditAids.start();
      window.AiHelperJournalEditAids.start();

      expect(instances).toHaveLength(2);
      expect(instances[0].disconnect).toHaveBeenCalledTimes(1);
      expect(instances[1].disconnect).not.toHaveBeenCalled();
    });

    it("releases the aids of a form removed from #history through the observer", async () => {
      dom = createJournalHistoryDOM(42);
      window.AiHelperJournalEditAids.start();
      const entry = window.AiHelperJournalEditAids.entryFor(dom.form);
      expect(entry).not.toBeUndefined();
      const typoDestroy = vi.spyOn(entry.typoChecker, "destroy");

      dom.change.remove();
      expect(dom.history.contains(dom.form)).toBe(false);
      await flushMicrotasks();

      expect(typoDestroy).toHaveBeenCalledTimes(1);
      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).toBeUndefined();
    });

    it("reports a form that fails to attach once, never retries it, and still releases detached forms", async () => {
      dom = createJournalHistoryDOM(42);
      window.AiHelperJournalEditAids.start();
      const entry = window.AiHelperJournalEditAids.entryFor(dom.form);
      const typoDestroy = vi.spyOn(entry.typoChecker, "destroy");
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});

      // A broken new form (no textarea) arrives together with the removal of the old one
      const broken = createJournalHistoryDOM(43);
      broken.textarea.closest(".jstBlock").remove();
      broken.history.remove();
      dom.history.appendChild(broken.change);
      dom.form.remove();
      await flushMicrotasks();

      expect(typoDestroy).toHaveBeenCalledTimes(1);
      expect(window.AiHelperJournalEditAids.entryFor(dom.form)).toBeUndefined();
      expect(window.AiHelperJournalEditAids.entryFor(broken.form)).toBeUndefined();
      expect(consoleError).toHaveBeenCalledTimes(1);
      expect(String(consoleError.mock.calls[0][0])).toContain("journal-43-form");

      // Any later mutation must not attach (and report) the broken form again
      dom.history.appendChild(document.createElement("div"));
      await flushMicrotasks();
      expect(consoleError).toHaveBeenCalledTimes(1);
    });

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

    const removeSpy = vi.spyOn(document, "removeEventListener");

    // The overlay lives inside the textarea's parent; it must not survive the form
    dom.form.remove();
    window.AiHelperJournalEditAids.releaseDetached();

    // The document-level listeners outlive the form unless destroy() removes them
    const removed = removeSpy.mock.calls.map((call) => call[0]);
    expect(removed).toContain("keydown");
    expect(removed).toContain("click");

    expect(document.querySelectorAll(".ai-helper-typo-overlay").length).toBe(0);
    expect(document.querySelectorAll(".ai-helper-typo-control-panel").length).toBe(0);
    expect(entry.typoChecker.overlay.isConnected).toBe(false);
  });
});
