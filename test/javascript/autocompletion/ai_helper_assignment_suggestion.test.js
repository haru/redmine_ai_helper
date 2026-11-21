import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";
import { flushPromises, installFetchStub } from "../support/fetch_stub.js";

describe("AiHelperAssignmentSuggestion", () => {
  let container;

  beforeEach(async () => {
    await loadScript("assets/javascripts/autocompletion/ai_helper_assignment_suggestion");
    container = document.createElement("div");
    document.body.appendChild(container);
  });

  afterEach(() => {
    container.remove();
    document.querySelectorAll('meta[name="csrf-token"]').forEach((m) => m.remove());
    vi.unstubAllGlobals();
  });

  function addMeta(name, content) {
    const meta = document.createElement("meta");
    meta.setAttribute("name", name);
    meta.setAttribute("content", content);
    document.head.appendChild(meta);
    return meta;
  }

  function addAssignedToField({ withCloseSibling = true } = {}) {
    const p = document.createElement("p");
    const select = document.createElement("select");
    select.id = "issue_assigned_to_id";
    p.appendChild(select);
    container.appendChild(p);

    if (withCloseSibling) {
      const nextP = document.createElement("p");
      nextP.textContent = "next field";
      container.appendChild(nextP);
    }

    return { p, select };
  }

  function createSuggestion(overrides = {}) {
    return new window.AiHelperAssignmentSuggestion({
      endpoint: "/issues/suggest_assignee",
      labels: {
        linkLabel: "Suggest assignee",
        loading: "Loading…",
        emptyContent: "Nothing to analyze",
        error: "Something went wrong",
        close: "Close",
      },
      robotIconHtml: "<svg></svg>",
      ...overrides,
    });
  }

  describe("init", () => {
    it("does nothing when the assigned-to select is absent", () => {
      const suggestion = createSuggestion();
      expect(() => suggestion.init()).not.toThrow();
      expect(suggestion.link).toBeNull();
    });

    it("does nothing when the select has no wrapping <p>", () => {
      const select = document.createElement("select");
      select.id = "issue_assigned_to_id";
      container.appendChild(select);
      const suggestion = createSuggestion();

      suggestion.init();

      expect(suggestion.link).toBeNull();
    });

    it("inserts a link with the escaped label and robot icon into the wrapping <p>", () => {
      const { p } = addAssignedToField();
      const suggestion = createSuggestion({ labels: { linkLabel: "<b>Suggest</b>" } });

      suggestion.init();

      expect(suggestion.link.parentNode).toBe(p);
      expect(suggestion.link.innerHTML).toContain("<svg></svg>");
      expect(suggestion.link.innerHTML).toContain("&lt;b&gt;Suggest&lt;/b&gt;");
    });

    it("opens the panel when the link is clicked and closes it on a second click", async () => {
      addAssignedToField();
      const suggestion = createSuggestion();
      vi.stubGlobal("fetch", vi.fn(() => new Promise(() => {})));
      suggestion.init();

      suggestion.link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      expect(suggestion.isOpen).toBe(true);
      expect(suggestion.panel).not.toBeNull();

      suggestion.link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      expect(suggestion.isOpen).toBe(false);
      expect(suggestion.panel).toBeNull();
    });
  });

  describe("fetchSuggestions", () => {
    it("shows an empty-content error without calling fetch when subject and description are blank", async () => {
      addAssignedToField();
      const suggestion = createSuggestion();
      suggestion.createPanel();
      const fetchMock = vi.fn();
      vi.stubGlobal("fetch", fetchMock);

      await suggestion.fetchSuggestions();

      expect(fetchMock).not.toHaveBeenCalled();
      expect(suggestion.panel.innerHTML).toContain("Nothing to analyze");
    });

    it("posts subject, description, tracker, and category with the CSRF token", async () => {
      addMeta("csrf-token", "tok-1");
      addAssignedToField();
      const subjectInput = document.createElement("input");
      subjectInput.id = "issue_subject";
      subjectInput.value = "Bug in login";
      const descriptionTextarea = document.createElement("textarea");
      descriptionTextarea.id = "issue_description";
      descriptionTextarea.value = "Steps to reproduce";
      const trackerSelect = document.createElement("select");
      trackerSelect.id = "issue_tracker_id";
      const trackerOption = document.createElement("option");
      trackerOption.value = "3";
      trackerSelect.appendChild(trackerOption);
      trackerSelect.value = "3";
      const categorySelect = document.createElement("select");
      categorySelect.id = "issue_category_id";
      const categoryOption = document.createElement("option");
      categoryOption.value = "7";
      categorySelect.appendChild(categoryOption);
      categorySelect.value = "7";
      container.append(subjectInput, descriptionTextarea, trackerSelect, categorySelect);

      const suggestion = createSuggestion();
      suggestion.createPanel();
      const fetchMock = vi.fn(async () => ({ ok: true, text: async () => "<div>ok</div>" }));
      vi.stubGlobal("fetch", fetchMock);

      await suggestion.fetchSuggestions();

      expect(fetchMock).toHaveBeenCalledTimes(1);
      const [url, options] = fetchMock.mock.calls[0];
      expect(url).toBe("/issues/suggest_assignee");
      expect(options.method).toBe("POST");
      expect(options.headers["X-CSRF-Token"]).toBe("tok-1");
      expect(JSON.parse(options.body)).toEqual({
        subject: "Bug in login",
        description: "Steps to reproduce",
        tracker_id: 3,
        category_id: 7,
      });
    });

    it("omits tracker_id and category_id when those fields are absent", async () => {
      addAssignedToField();
      const subjectInput = document.createElement("input");
      subjectInput.id = "issue_subject";
      subjectInput.value = "Just a subject";
      container.appendChild(subjectInput);

      const suggestion = createSuggestion();
      suggestion.createPanel();
      const fetchMock = vi.fn(async () => ({ ok: true, text: async () => "<div>ok</div>" }));
      vi.stubGlobal("fetch", fetchMock);

      await suggestion.fetchSuggestions();

      const body = JSON.parse(fetchMock.mock.calls[0][1].body);
      expect(body).toEqual({ subject: "Just a subject", description: "" });
    });

    it("renders the server HTML on success", async () => {
      addAssignedToField();
      const subjectInput = document.createElement("input");
      subjectInput.id = "issue_subject";
      subjectInput.value = "Subject";
      container.appendChild(subjectInput);

      const suggestion = createSuggestion();
      suggestion.createPanel();
      vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, text: async () => '<div class="result">Alice</div>' })));

      await suggestion.fetchSuggestions();

      expect(suggestion.panel.innerHTML).toContain("Alice");
    });

    it("renders an error when the server responds with a non-ok status", async () => {
      addAssignedToField();
      const subjectInput = document.createElement("input");
      subjectInput.id = "issue_subject";
      subjectInput.value = "Subject";
      container.appendChild(subjectInput);

      const suggestion = createSuggestion();
      suggestion.createPanel();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
      vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false })));

      await suggestion.fetchSuggestions();

      expect(suggestion.panel.innerHTML).toContain("Something went wrong");
      expect(errorSpy).toHaveBeenCalled();
      errorSpy.mockRestore();
    });

    it("renders an error when fetch itself rejects", async () => {
      addAssignedToField();
      const subjectInput = document.createElement("input");
      subjectInput.id = "issue_subject";
      subjectInput.value = "Subject";
      container.appendChild(subjectInput);

      const suggestion = createSuggestion();
      suggestion.createPanel();
      const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
      vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("network down"); }));

      await suggestion.fetchSuggestions();

      expect(suggestion.panel.innerHTML).toContain("Something went wrong");
      errorSpy.mockRestore();
    });
  });

  describe("renderHtml", () => {
    it("does nothing when there is no panel", () => {
      const suggestion = createSuggestion();
      expect(() => suggestion.renderHtml("<div></div>")).not.toThrow();
    });

    it("wires up user selection and close button clicks", () => {
      addAssignedToField();
      const assignedToSelect = document.getElementById("issue_assigned_to_id");
      const option = document.createElement("option");
      option.value = "42";
      assignedToSelect.appendChild(option);

      const suggestion = createSuggestion();
      suggestion.createPanel();
      suggestion.isOpen = true;
      suggestion.renderHtml(
        '<a href="#" class="ai-helper-suggest-assignee-user" data-user-id="42">Alice</a>' +
          '<a href="#" class="ai-helper-suggest-assignee-close-btn">Close</a>',
      );

      const selectUserSpy = vi.spyOn(suggestion, "selectUser");
      suggestion.panel.querySelector(".ai-helper-suggest-assignee-user")
        .dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      expect(selectUserSpy).toHaveBeenCalledWith("42");

      suggestion.panel.querySelector(".ai-helper-suggest-assignee-close-btn")
        .dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      expect(suggestion.isOpen).toBe(false);
    });

    it("does not throw when no close button is present in the response", () => {
      addAssignedToField();
      const suggestion = createSuggestion();
      suggestion.createPanel();

      expect(() => suggestion.renderHtml("<div>no controls</div>")).not.toThrow();
    });
  });

  describe("selectUser", () => {
    it("does nothing when the assigned-to select is absent", () => {
      const suggestion = createSuggestion();
      expect(() => suggestion.selectUser("1")).not.toThrow();
    });

    it("sets the select value and dispatches a change event", () => {
      const { select } = addAssignedToField();
      const option = document.createElement("option");
      option.value = "9";
      select.appendChild(option);

      const suggestion = createSuggestion();
      let changeFired = false;
      select.addEventListener("change", () => { changeFired = true; });

      suggestion.selectUser("9");

      expect(select.value).toBe("9");
      expect(changeFired).toBe(true);
    });

    it("hides the assign-to-me link when the selected user matches the current user", () => {
      addAssignedToField();
      const assignToMeLink = document.createElement("a");
      assignToMeLink.className = "assign-to-me-link";
      assignToMeLink.dataset.id = "9";
      container.appendChild(assignToMeLink);

      const suggestion = createSuggestion();
      suggestion.selectUser("9");

      expect(assignToMeLink.style.display).toBe("none");
    });

    it("shows the assign-to-me link when the selected user differs from the current user", () => {
      addAssignedToField();
      const assignToMeLink = document.createElement("a");
      assignToMeLink.className = "assign-to-me-link";
      assignToMeLink.dataset.id = "9";
      assignToMeLink.style.display = "none";
      container.appendChild(assignToMeLink);

      const suggestion = createSuggestion();
      suggestion.selectUser("10");

      expect(assignToMeLink.style.display).toBe("");
    });

    it("does not throw when there is no assign-to-me link on the page", () => {
      addAssignedToField();
      const suggestion = createSuggestion();
      expect(() => suggestion.selectUser("9")).not.toThrow();
    });
  });

  describe("renderError", () => {
    it("does nothing when there is no panel", () => {
      const suggestion = createSuggestion();
      expect(() => suggestion.renderError("boom")).not.toThrow();
    });

    it("renders the escaped message with a working close button", () => {
      addAssignedToField();
      const suggestion = createSuggestion();
      suggestion.createPanel();
      suggestion.isOpen = true;

      suggestion.renderError("<img onerror=alert(1)>");

      expect(suggestion.panel.innerHTML).toContain("&lt;img");
      expect(suggestion.panel.innerHTML).not.toContain("<img onerror");

      suggestion.panel.querySelector(".ai-helper-suggest-assignee-close-btn")
        .dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      expect(suggestion.isOpen).toBe(false);
    });
  });

  describe("createPanel", () => {
    it("replaces an existing panel rather than stacking a new one", () => {
      addAssignedToField();
      const suggestion = createSuggestion();

      suggestion.createPanel();
      const firstPanel = suggestion.panel;
      suggestion.createPanel();

      expect(suggestion.panel).not.toBe(firstPanel);
      expect(firstPanel.isConnected).toBe(false);
      expect(container.querySelectorAll(".ai-helper-suggest-assignee-panel").length).toBe(1);
    });
  });

  // --- Re-render release (088-fix-issue-form-rerender): destroy() must
  // remove the link/panel and cancel the in-flight request so a response
  // belonging to a detached form never reaches the new form (CRF-061). ---

  /** Helper: Add the subject input fetchSuggestions reads. */
  function addSubjectInput(value = "Bug in login") {
    const input = document.createElement("input");
    input.id = "issue_subject";
    input.value = value;
    container.appendChild(input);
    return input;
  }

  describe("destroy (088-fix-issue-form-rerender)", () => {
    let errorSpy;

    beforeEach(() => {
      errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    });

    afterEach(() => {
      errorSpy.mockRestore();
    });

    it("sets destroyed, removes the link and the panel from the DOM", () => {
      addAssignedToField();
      const suggestion = createSuggestion();
      suggestion.init();
      suggestion.open();
      expect(document.querySelector(".ai-helper-suggest-assignee-link")).not.toBeNull();
      expect(document.querySelector(".ai-helper-suggest-assignee-panel")).not.toBeNull();

      suggestion.destroy();

      expect(suggestion.destroyed).toBe(true);
      expect(suggestion.link).toBeNull();
      expect(document.querySelector(".ai-helper-suggest-assignee-link")).toBeNull();
      expect(document.querySelector(".ai-helper-suggest-assignee-panel")).toBeNull();
    });

    it("does not throw when the link was never created", () => {
      const suggestion = createSuggestion();
      expect(() => suggestion.destroy()).not.toThrow();
      expect(suggestion.destroyed).toBe(true);
    });

    it("aborts an unfinished fetch", () => {
      addAssignedToField();
      addSubjectInput();
      const suggestion = createSuggestion();
      suggestion.init();
      const fetchStub = installFetchStub();

      suggestion.open();
      expect(fetchStub.calls.length).toBe(1);
      suggestion.destroy();

      expect(fetchStub.calls[0].options.signal.aborted).toBe(true);
    });

    it("ignores a response arriving after destroy() and never selects a user", async () => {
      addAssignedToField();
      addSubjectInput();
      const suggestion = createSuggestion();
      suggestion.init();
      const fetchStub = installFetchStub();

      suggestion.open();
      suggestion.destroy();
      const renderSpy = vi.spyOn(suggestion, "renderHtml");
      fetchStub.calls[0].resolve("<div>Late response</div>");
      await flushPromises();

      expect(renderSpy).not.toHaveBeenCalled();
      expect(document.querySelector(".ai-helper-suggest-assignee-panel")).toBeNull();
      expect(document.getElementById("issue_assigned_to_id").value).toBe("");
      expect(errorSpy).not.toHaveBeenCalled();
    });

    it("ignores an error arriving after destroy()", async () => {
      addAssignedToField();
      addSubjectInput();
      const suggestion = createSuggestion();
      suggestion.init();
      const fetchStub = installFetchStub();

      suggestion.open();
      suggestion.destroy();
      fetchStub.calls[0].reject(new Error("boom"));
      await flushPromises();

      expect(document.querySelector(".ai-helper-suggest-assignee-panel")).toBeNull();
      expect(errorSpy).not.toHaveBeenCalled();
    });

    it("close() aborts an unfinished fetch", () => {
      addAssignedToField();
      addSubjectInput();
      const suggestion = createSuggestion();
      suggestion.init();
      const fetchStub = installFetchStub();

      suggestion.open();
      suggestion.close();

      expect(fetchStub.calls[0].options.signal.aborted).toBe(true);
    });

    it("ignores the previous response when closed and opened again", async () => {
      addAssignedToField();
      addSubjectInput();
      const suggestion = createSuggestion();
      suggestion.init();
      const fetchStub = installFetchStub();

      suggestion.open();
      suggestion.close();
      suggestion.open();
      expect(fetchStub.calls.length).toBe(2);

      fetchStub.calls[0].resolve("<div>Old response</div>");
      await flushPromises();
      expect(suggestion.panel.innerHTML).not.toContain("Old response");
      expect(suggestion.panel.innerHTML).toContain("Loading");

      fetchStub.calls[1].resolve("<div>New response</div>");
      await flushPromises();
      expect(suggestion.panel.innerHTML).toContain("New response");
      expect(errorSpy).not.toHaveBeenCalled();
    });

    it("close() releases the controller so the aborted request no longer owns the instance", () => {
      addAssignedToField();
      addSubjectInput();
      const suggestion = createSuggestion();
      suggestion.init();
      installFetchStub();

      suggestion.open();
      expect(suggestion.abortController).not.toBeNull();
      suggestion.close();

      expect(suggestion.abortController).toBeNull();
    });

    it("ignores a non-abort error of a superseded open() (closed and opened again)", async () => {
      addAssignedToField();
      addSubjectInput();
      const suggestion = createSuggestion();
      suggestion.init();
      const fetchStub = installFetchStub();

      suggestion.open();
      suggestion.close();
      suggestion.open();
      expect(fetchStub.calls.length).toBe(2);

      // The first request fails with a plain error, not an AbortError: only
      // the ownership check can drop it
      fetchStub.calls[0].reject(new Error("late failure"));
      await flushPromises();

      expect(errorSpy).not.toHaveBeenCalled();
      expect(suggestion.panel.innerHTML).toContain("Loading");
      expect(suggestion.panel.innerHTML).not.toContain("Something went wrong");
    });

    it.each([["init"], ["open"]])("%s() throws on a destroyed instance instead of touching the new form", (method) => {
      addAssignedToField();
      const suggestion = createSuggestion();
      suggestion.destroy();

      expect(() => suggestion[method]()).toThrow("destroyed");

      expect(document.querySelector(".ai-helper-suggest-assignee-link")).toBeNull();
      expect(document.querySelector(".ai-helper-suggest-assignee-panel")).toBeNull();
    });

    it("does not display or log an abort-caused AbortError", async () => {
      addAssignedToField();
      addSubjectInput();
      const suggestion = createSuggestion();
      suggestion.init();
      const fetchStub = installFetchStub();

      suggestion.open();
      suggestion.close();
      const abortError = new Error("The user aborted a request.");
      abortError.name = "AbortError";
      fetchStub.calls[0].reject(abortError);
      await flushPromises();

      expect(errorSpy).not.toHaveBeenCalled();
      expect(document.querySelector(".ai-helper-suggest-assignee-panel")).toBeNull();
    });
  });
});
