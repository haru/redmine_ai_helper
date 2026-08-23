import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";
import { loadScriptAndFireDOMContentLoaded } from "../support/dom_content_loaded.js";

// T040: characterization tests for issues/_bottom.html.erb extraction.

describe("ai_helper_issue_summary", () => {
  let fieldset;
  let aiHelperMock;
  let showAndScrollToSpy;
  let cleanup;
  let extraElements;

  function track(el) {
    extraElements.push(el);
    return el;
  }

  function addFieldset(config = {}) {
    fieldset = document.createElement("fieldset");
    fieldset.id = "ai-helper-summary-fields";
    fieldset.className = "collapsible collapsed";
    const legend = document.createElement("legend");
    fieldset.appendChild(legend);
    fieldset.dataset.config = JSON.stringify({
      userId: 7,
      summaryUrl: "/issues/1/ai_helper/summary",
      generateUrl: "/issues/1/ai_helper/generate_summary",
      similarIssuesUrl: "/issues/1/ai_helper/similar_issues",
      errorMessage: "Error occurred",
      hasSummary: false,
      ...config,
    });
    document.body.appendChild(fieldset);
    return fieldset;
  }

  beforeEach(() => {
    extraElements = [];
    aiHelperMock = { generateSummaryStream: vi.fn() };
    vi.stubGlobal("ai_helper", aiHelperMock);
    vi.stubGlobal("toggleFieldset", vi.fn((legend) => {
      legend.closest("fieldset").classList.toggle("collapsed");
    }));
    showAndScrollToSpy = vi.fn();
    vi.stubGlobal("showAndScrollTo", showAndScrollToSpy);
    // Real dependency lives in ai_helper_collapsible_fieldset.js (loaded
    // separately in production via html_header); stub an equivalent here.
    vi.stubGlobal("AiHelperCollapsibleFieldset", {
      setExpanded(fieldsetId, flag) {
        const el = document.getElementById(fieldsetId);
        if (!el) {return;}
        const legend = el.querySelector("legend");
        const isOpen = !el.classList.contains("collapsed");
        if (isOpen !== flag) {
          toggleFieldset(legend);
        }
      },
    });
  });

  afterEach(() => {
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    fieldset?.remove();
    fieldset = undefined;
    extraElements.forEach((el) => el.remove());
    extraElements = [];
    vi.unstubAllGlobals();
    localStorage.clear();
    delete window.getSummary;
    delete window.generateSummaryStream;
    delete window.aiHelperSaveSummaryState;
    delete window.findSimilarIssues;
  });

  function stubXHR() {
    let createdInstance;
    function MockXHR() {
      this.open = vi.fn();
      this.send = vi.fn();
      createdInstance = this;
    }
    vi.stubGlobal("XMLHttpRequest", MockXHR);
    return () => createdInstance;
  }

  describe("getSummary", () => {
    it("shows a loader, then renders the response on success", async () => {
      addFieldset();
      const summaryArea = track(document.createElement("div"));
      summaryArea.id = "ai-helper-summary-area";
      document.body.appendChild(summaryArea);
      const getInstance = stubXHR();

      await loadScript("assets/javascripts/summary/ai_helper_issue_summary");
      window.getSummary();

      expect(getInstance().open).toHaveBeenCalledWith("GET", "/issues/1/ai_helper/summary", true);
      getInstance().status = 200;
      getInstance().responseText = "<p>summary</p>";
      getInstance().onload();

      expect(summaryArea.innerHTML).toBe("<p>summary</p>");
    });

    it("appends ?update=true when update is requested", async () => {
      addFieldset();
      const getInstance = stubXHR();
      await loadScript("assets/javascripts/summary/ai_helper_issue_summary");
      window.getSummary(true);

      expect(getInstance().open).toHaveBeenCalledWith("GET", "/issues/1/ai_helper/summary?update=true", true);
    });

    it("shows an error message with status text on a non-200 response", async () => {
      addFieldset();
      const summaryArea = track(document.createElement("div"));
      summaryArea.id = "ai-helper-summary-area";
      document.body.appendChild(summaryArea);
      const getInstance = stubXHR();

      await loadScript("assets/javascripts/summary/ai_helper_issue_summary");
      window.getSummary();
      getInstance().status = 500;
      getInstance().statusText = "Internal Server Error";
      getInstance().onload();

      expect(summaryArea.innerHTML).toBe('<div class="error">Error occurred: Internal Server Error</div>');
    });

    it("shows an error message on network error", async () => {
      addFieldset();
      const summaryArea = track(document.createElement("div"));
      summaryArea.id = "ai-helper-summary-area";
      document.body.appendChild(summaryArea);
      const getInstance = stubXHR();

      await loadScript("assets/javascripts/summary/ai_helper_issue_summary");
      window.getSummary();
      getInstance().onerror();

      expect(summaryArea.innerHTML).toBe('<div class="error">Error occurred</div>');
    });
  });

  describe("generateSummaryStream", () => {
    it("delegates to ai_helper.generateSummaryStream with the configured URL and error message", async () => {
      addFieldset({ generateUrl: "/gen", errorMessage: "boom" });
      await loadScript("assets/javascripts/summary/ai_helper_issue_summary");

      window.generateSummaryStream();

      expect(aiHelperMock.generateSummaryStream).toHaveBeenCalledWith("/gen", "boom");
    });
  });

  describe("aiHelperSaveSummaryState (window-exposed)", () => {
    it("saves 'expanded' to localStorage when the fieldset is not collapsed", async () => {
      addFieldset({ userId: 42 });
      fieldset.classList.remove("collapsed");
      await loadScript("assets/javascripts/summary/ai_helper_issue_summary");

      window.aiHelperSaveSummaryState();

      expect(localStorage.getItem("aiHelperIssueSummaryState_42")).toBe("expanded");
    });
  });

  describe("findSimilarIssues (window-exposed)", () => {
    it("fetches similar issues for the checked scope and renders the response", async () => {
      addFieldset({ similarIssuesUrl: "/similar" });
      const radio = track(document.createElement("input"));
      radio.type = "radio";
      radio.name = "ai_helper_scope";
      radio.value = "all";
      radio.checked = true;
      document.body.appendChild(radio);
      const area = track(document.createElement("div"));
      area.id = "ai-helper-similar-issues-area";
      document.body.appendChild(area);
      const getInstance = stubXHR();

      await loadScript("assets/javascripts/summary/ai_helper_issue_summary");
      window.findSimilarIssues();

      expect(getInstance().open).toHaveBeenCalledWith("GET", "/similar?scope=all", true);
      getInstance().status = 200;
      getInstance().responseText = "<p>results</p>";
      getInstance().onload();

      expect(area.innerHTML).toBe("<p>results</p>");
    });

    it("defaults to with_subprojects scope when nothing is checked", async () => {
      addFieldset({ similarIssuesUrl: "/similar" });
      const getInstance = stubXHR();

      await loadScript("assets/javascripts/summary/ai_helper_issue_summary");
      window.findSimilarIssues();

      expect(getInstance().open).toHaveBeenCalledWith("GET", "/similar?scope=with_subprojects", true);
    });
  });

  describe("effort estimation UI (wired up via DOMContentLoaded, driven through the similar-issues area)", () => {
    function addSimilarIssuesArea() {
      const area = track(document.createElement("div"));
      area.id = "ai-helper-similar-issues-area";
      document.body.appendChild(area);
      return area;
    }

    function addEffortCheckbox(area, { checked = false, spentHours, similarityScore } = {}) {
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.className = "ai-helper-effort-checkbox";
      checkbox.checked = checked;
      if (spentHours !== undefined) {checkbox.dataset.spentHours = String(spentHours);}
      if (similarityScore !== undefined) {checkbox.dataset.similarityScore = String(similarityScore);}
      area.appendChild(checkbox);
      return checkbox;
    }

    function addSuggestedHoursBlock(area, noteTemplate = "%{count} issues") {
      const block = document.createElement("div");
      block.id = "ai-helper-suggested-hours-block";
      block.dataset.noteTemplate = noteTemplate;
      block.style.display = "none";
      const valueSpan = document.createElement("span");
      valueSpan.id = "ai-helper-suggested-hours-value";
      const noteSpan = document.createElement("span");
      noteSpan.id = "ai-helper-suggested-hours-note";
      block.appendChild(valueSpan);
      block.appendChild(noteSpan);
      area.appendChild(block);
      return { block, valueSpan, noteSpan };
    }

    it("recalculates the weighted suggested hours when an effort checkbox changes", async () => {
      addFieldset();
      const area = addSimilarIssuesArea();
      const { block, valueSpan, noteSpan } = addSuggestedHoursBlock(area);
      const cb1 = addEffortCheckbox(area, { checked: true, spentHours: 4, similarityScore: 0.8 });
      addEffortCheckbox(area, { checked: false, spentHours: 10, similarityScore: 0.5 });

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/summary/ai_helper_issue_summary");
      cb1.dispatchEvent(new Event("change", { bubbles: true }));

      expect(block.style.display).toBe("");
      expect(valueSpan.textContent).toBe("4.0");
      expect(noteSpan.textContent).toBe("(1 issues)");
    });

    it("hides the suggested-hours block when nothing is checked", async () => {
      addFieldset();
      const area = addSimilarIssuesArea();
      const { block } = addSuggestedHoursBlock(area);
      addEffortCheckbox(area, { checked: false, spentHours: 4, similarityScore: 0.8 });

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/summary/ai_helper_issue_summary");

      expect(block.style.display).toBe("none");
    });

    it("skips checkboxes missing spent-hours/similarity data from the weighted average", async () => {
      addFieldset();
      const area = addSimilarIssuesArea();
      const { valueSpan } = addSuggestedHoursBlock(area);
      addEffortCheckbox(area, { checked: true, similarityScore: 0.8 }); // no spentHours -> NaN, skipped
      const cb2 = addEffortCheckbox(area, { checked: true, spentHours: 6, similarityScore: 1 });

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/summary/ai_helper_issue_summary");
      cb2.dispatchEvent(new Event("change", { bubbles: true }));

      expect(valueSpan.textContent).toBe("6.0");
    });

    it("toggles all effort checkboxes and recomputes when the select-all checkbox changes", async () => {
      addFieldset();
      const area = addSimilarIssuesArea();
      addSuggestedHoursBlock(area);
      const cb1 = addEffortCheckbox(area, { checked: false, spentHours: 2, similarityScore: 1 });
      const cb2 = addEffortCheckbox(area, { checked: false, spentHours: 4, similarityScore: 1 });
      const selectAll = document.createElement("input");
      selectAll.type = "checkbox";
      selectAll.id = "ai-helper-effort-select-all";
      area.appendChild(selectAll);

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/summary/ai_helper_issue_summary");
      selectAll.checked = true;
      selectAll.dispatchEvent(new Event("change", { bubbles: true }));

      expect(cb1.checked).toBe(true);
      expect(cb2.checked).toBe(true);
    });

    it("sets the select-all checkbox to indeterminate when only some rows are checked", async () => {
      addFieldset();
      const area = addSimilarIssuesArea();
      addSuggestedHoursBlock(area);
      addEffortCheckbox(area, { checked: true, spentHours: 2, similarityScore: 1 });
      addEffortCheckbox(area, { checked: false, spentHours: 4, similarityScore: 1 });
      const selectAll = document.createElement("input");
      selectAll.type = "checkbox";
      selectAll.id = "ai-helper-effort-select-all";
      area.appendChild(selectAll);

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/summary/ai_helper_issue_summary");

      expect(selectAll.indeterminate).toBe(true);
      expect(selectAll.checked).toBe(false);
    });

    it("applies the suggested hours to the estimated-hours field and scrolls to it", async () => {
      addFieldset();
      const area = addSimilarIssuesArea();
      const { valueSpan } = addSuggestedHoursBlock(area);
      valueSpan.textContent = "3.5";
      const applyButton = document.createElement("a");
      applyButton.id = "ai-helper-apply-suggested-hours";
      area.appendChild(applyButton);
      const estimatedHoursField = track(document.createElement("input"));
      estimatedHoursField.id = "issue_estimated_hours";
      document.body.appendChild(estimatedHoursField);

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/summary/ai_helper_issue_summary");
      applyButton.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(estimatedHoursField.value).toBe("3.5");
      expect(showAndScrollToSpy).toHaveBeenCalledWith("update", "issue_estimated_hours");
    });
  });

  describe("similar issues section relocation and fieldset restore (DOMContentLoaded)", () => {
    it("moves the similar-issues section to just after #relations", async () => {
      addFieldset();
      const relations = track(document.createElement("div"));
      relations.id = "relations";
      document.body.appendChild(relations);
      const similarSection = track(document.createElement("div"));
      similarSection.id = "ai-helper-similar-issues-section";
      document.body.appendChild(similarSection);

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/summary/ai_helper_issue_summary");

      expect(relations.nextElementSibling).toBe(similarSection);
    });

    it("expands the summary fieldset when a prior 'expanded' state is saved", async () => {
      addFieldset({ userId: 1 });
      localStorage.setItem("aiHelperIssueSummaryState_1", "expanded");

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/summary/ai_helper_issue_summary");

      expect(fieldset.classList.contains("collapsed")).toBe(false);
    });

    it("auto-loads the summary when hasSummary is true", async () => {
      addFieldset({ hasSummary: true, summaryUrl: "/auto-load" });
      const getInstance = stubXHR();

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/summary/ai_helper_issue_summary");

      expect(getInstance().open).toHaveBeenCalledWith("GET", "/auto-load", true);
    });

    it("does nothing when the fieldset is absent", async () => {
      await expect(loadScriptAndFireDOMContentLoaded("assets/javascripts/summary/ai_helper_issue_summary")).resolves.toBeDefined();
    });
  });
});
