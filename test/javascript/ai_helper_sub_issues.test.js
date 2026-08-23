import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "./support/load_script.js";
import { loadScriptAndFireDOMContentLoaded } from "./support/dom_content_loaded.js";

// ai_helper_sub_issues.js is an IIFE with no window-exposed API; it wires up
// DOM event listeners and a MutationObserver on load. We drive it purely
// through DOM events and fetch stubbing.

describe("ai_helper_sub_issues (IIFE)", () => {
  let container;
  let fetchMock;
  let registeredListeners;
  let observerInstances;

  beforeEach(() => {
    container = document.createElement("div");
    container.id = "content";
    document.body.appendChild(container);
    registeredListeners = [];
    observerInstances = [];
  });

  afterEach(() => {
    registeredListeners.forEach(([type, listener, options]) => {
      document.removeEventListener(type, listener, options);
    });
    observerInstances.forEach((observer) => observer.disconnect());
    container.remove();
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  function createTrackerSelect({
    trackerId = "1",
    projectId = "5",
    rowIndex = "0",
    assigneeSelectId,
    extraOptionValues = [],
    wrapInDiv = false,
  } = {}) {
    const select = document.createElement("select");
    select.className = "sub-issue-tracker-select";
    select.dataset.projectId = projectId;
    select.dataset.rowIndex = rowIndex;

    for (const value of new Set([trackerId, ...extraOptionValues].filter((v) => v !== undefined))) {
      const option = document.createElement("option");
      option.value = value;
      select.appendChild(option);
    }
    select.value = trackerId || "";

    const mountPoint = wrapInDiv ? document.createElement("div") : container;
    mountPoint.appendChild(select);
    if (wrapInDiv) {container.appendChild(mountPoint);}

    const assigneeSelect = document.createElement("select");
    assigneeSelect.id = assigneeSelectId || `sub_issues_assigned_to_id_${rowIndex}`;
    container.appendChild(assigneeSelect);

    return { select, assigneeSelect };
  }

  function stubFetch(implementation) {
    fetchMock = vi.fn(implementation);
    vi.stubGlobal("fetch", fetchMock);
    return fetchMock;
  }

  async function load() {
    // ai_helper_sub_issues.js registers a document-level 'change' listener
    // and a MutationObserver every time its top-level IIFE runs, and
    // loadScript() re-runs that IIFE fresh on every call. Track both here so
    // afterEach can tear them down and keep tests order-independent.
    const originalAddEventListener = Document.prototype.addEventListener;
    const addEventListenerSpy = vi
      .spyOn(document, "addEventListener")
      .mockImplementation(function(type, listener, options) {
        registeredListeners.push([type, listener, options]);
        return originalAddEventListener.call(document, type, listener, options);
      });

    const OriginalMutationObserver = globalThis.MutationObserver;
    class TrackedMutationObserver extends OriginalMutationObserver {
      constructor(...args) {
        super(...args);
        observerInstances.push(this);
      }
    }
    vi.stubGlobal("MutationObserver", TrackedMutationObserver);

    await loadScript("assets/javascripts/ai_helper_sub_issues");
    addEventListenerSpy.mockRestore();
    // Initial init runs on a 100ms setTimeout.
    await new Promise((resolve) => setTimeout(resolve, 150));
  }

  it("loads assignees for trackers that already have a value on init", async () => {
    const { select, assigneeSelect } = createTrackerSelect({ trackerId: "2", projectId: "7", rowIndex: "3" });
    stubFetch(async () => ({
      ok: true,
      json: async () => [{ id: 10, name: "Alice" }, { id: 11, name: "Bob" }],
    }));

    await load();

    expect(fetchMock).toHaveBeenCalledWith("/projects/7/ai_helper/assignable_users?tracker_id=2");
    expect(assigneeSelect.querySelectorAll("option").length).toBe(3);
    expect(assigneeSelect.querySelectorAll("option")[1].textContent).toBe("Alice");
    void select;
  });

  it("does not fetch when the tracker select has no value on init", async () => {
    createTrackerSelect({ trackerId: "" });
    stubFetch(async () => ({ ok: true, json: async () => [] }));

    await load();

    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("loads assignees when a tracker select changes", async () => {
    const { select, assigneeSelect } = createTrackerSelect({
      trackerId: "",
      projectId: "9",
      rowIndex: "1",
      extraOptionValues: ["4"],
    });
    stubFetch(async () => ({
      ok: true,
      json: async () => [{ id: 1, name: "Carol" }],
    }));

    await load();
    fetchMock.mockClear();

    select.value = "4";
    select.dispatchEvent(new Event("change", { bubbles: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(fetchMock).toHaveBeenCalledWith("/projects/9/ai_helper/assignable_users?tracker_id=4");
    expect(assigneeSelect.querySelectorAll("option").length).toBe(2);
  });

  it("preserves the current assignee selection when the option is still present", async () => {
    const { select, assigneeSelect } = createTrackerSelect({ trackerId: "1", projectId: "1", rowIndex: "2" });
    stubFetch(async () => ({
      ok: true,
      json: async () => [{ id: 5, name: "Dave" }],
    }));

    await load();
    assigneeSelect.value = "5";

    select.dispatchEvent(new Event("change", { bubbles: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(assigneeSelect.value).toBe("5");
  });

  it("does nothing on change events for unrelated elements", async () => {
    createTrackerSelect({ trackerId: "" });
    const other = document.createElement("select");
    container.appendChild(other);
    stubFetch(async () => ({ ok: true, json: async () => [] }));

    await load();
    fetchMock.mockClear();

    other.dispatchEvent(new Event("change", { bubbles: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("skips fetching when required data attributes are missing", async () => {
    const select = document.createElement("select");
    select.className = "sub-issue-tracker-select";
    // no data-project-id / data-row-index
    select.value = "1";
    const option = document.createElement("option");
    option.value = "1";
    select.appendChild(option);
    select.value = "1";
    container.appendChild(select);
    stubFetch(async () => ({ ok: true, json: async () => [] }));

    await load();

    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("logs an error and leaves the assignee select untouched when the fetch fails", async () => {
    const { assigneeSelect } = createTrackerSelect({ trackerId: "1", projectId: "1", rowIndex: "0" });
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    stubFetch(async () => ({ ok: false, status: 500 }));

    await load();

    expect(errorSpy).toHaveBeenCalledWith("Failed to load assignable users:", expect.any(Error));
    expect(assigneeSelect.querySelectorAll("option").length).toBe(0);
    errorSpy.mockRestore();
  });

  it("initializes newly-added tracker selects detected by the MutationObserver", async () => {
    // No tracker select present at load time -> initializeAllTrackers is a no-op.
    stubFetch(async () => ({ ok: true, json: async () => [{ id: 1, name: "Erin" }] }));
    await load();
    expect(fetchMock).not.toHaveBeenCalled();

    // The observer's check uses querySelector() on each added node, which only
    // matches descendants -- so the select must arrive nested inside a wrapper
    // element (as it would when a server-rendered row fragment is inserted).
    const { assigneeSelect } = createTrackerSelect({
      trackerId: "3",
      projectId: "2",
      rowIndex: "0",
      wrapInDiv: true,
    });
    // MutationObserver callbacks run as a microtask after the mutation.
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(fetchMock).toHaveBeenCalledWith("/projects/2/ai_helper/assignable_users?tracker_id=3");
    expect(assigneeSelect.querySelectorAll("option").length).toBe(2);
  });

  it("falls back to observing document.body when #content is absent", async () => {
    container.remove();
    stubFetch(async () => ({ ok: true, json: async () => [] }));

    await expect(load()).resolves.toBeUndefined();
  });
});

// T041: characterization tests for issues/subissues/_index.html.erb (T030)
// and issues/subissues/_description_bottom.html.erb (T031) extraction.

describe("aiHelperGenerateSubIssues (window-exposed, from subissues/_index.html.erb)", () => {
  let wrapper;
  let resultContainer;
  let instructionsField;
  let meta;

  beforeEach(async () => {
    wrapper = document.createElement("div");
    wrapper.id = "ai-helper-subissues-index";
    wrapper.dataset.config = JSON.stringify({ generateUrl: "/issues/5/ai_helper/subissue_gen" });
    document.body.appendChild(wrapper);

    resultContainer = document.createElement("div");
    resultContainer.id = "ai-helper-generated-subissues";
    document.body.appendChild(resultContainer);

    instructionsField = document.createElement("textarea");
    instructionsField.id = "ai_helper_subissues_instructions";
    instructionsField.value = "split by component";
    document.body.appendChild(instructionsField);

    meta = document.createElement("meta");
    meta.name = "csrf-token";
    meta.content = "test-csrf-token";
    document.head.appendChild(meta);

    await loadScript("assets/javascripts/ai_helper_sub_issues");
  });

  afterEach(() => {
    wrapper.remove();
    resultContainer.remove();
    instructionsField.remove();
    meta.remove();
    vi.unstubAllGlobals();
    delete window.aiHelperGenerateSubIssues;
  });

  it("shows a loader, then POSTs the instructions with CSRF token and renders the response", async () => {
    let capturedUrl;
    let capturedOptions;
    const fetchMock = vi.fn((url, options) => {
      capturedUrl = url;
      capturedOptions = options;
      expect(resultContainer.innerHTML).toContain("ai-helper-loader");
      return Promise.resolve({ text: () => Promise.resolve("<p>drafted</p>") });
    });
    vi.stubGlobal("fetch", fetchMock);

    window.aiHelperGenerateSubIssues(5);
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(capturedUrl).toBe("/issues/5/ai_helper/subissue_gen");
    expect(capturedOptions.method).toBe("POST");
    expect(capturedOptions.headers["X-CSRF-Token"]).toBe("test-csrf-token");
    expect(JSON.parse(capturedOptions.body)).toEqual({ instructions: "split by component" });
    expect(resultContainer.innerHTML).toBe("<p>drafted</p>");
  });

  it("shows an error message when the request fails", async () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    vi.stubGlobal("fetch", vi.fn(() => Promise.reject(new Error("network down"))));

    window.aiHelperGenerateSubIssues(5);
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(resultContainer.innerHTML).toBe("<p>Error generating sub issues. Please try again later.</p>");
    expect(errorSpy).toHaveBeenCalled();
    errorSpy.mockRestore();
  });
});

describe("showSubissuerGenerator and menu/area relocation (window-exposed, from subissues/_description_bottom.html.erb)", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    delete window.showSubissuerGenerator;
  });

  it("toggles the generator area's display between 'none' and 'block'", async () => {
    const generatorArea = document.createElement("div");
    generatorArea.id = "ai-helper-subissuer-generator-area";
    generatorArea.style.display = "none";
    document.body.appendChild(generatorArea);

    await loadScript("assets/javascripts/ai_helper_sub_issues");
    window.showSubissuerGenerator();
    expect(generatorArea.style.display).toBe("block");

    window.showSubissuerGenerator();
    expect(generatorArea.style.display).toBe("none");

    generatorArea.remove();
  });

  it("moves the generator menu span to be the first child of #issue_tree > .contextual, and relocates the generator area into #issue_tree (hidden)", async () => {
    const issueTree = document.createElement("div");
    issueTree.id = "issue_tree";
    const contextual = document.createElement("div");
    contextual.className = "contextual";
    const existingChild = document.createElement("span");
    contextual.appendChild(existingChild);
    issueTree.appendChild(contextual);
    document.body.appendChild(issueTree);

    const menuSpan = document.createElement("span");
    menuSpan.id = "ai-helper-subissuer-generator-menu";
    document.body.appendChild(menuSpan);

    const generatorArea = document.createElement("div");
    generatorArea.id = "ai-helper-subissuer-generator-area";
    generatorArea.style.display = "block";
    document.body.appendChild(generatorArea);

    const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_sub_issues");

    expect(contextual.firstChild).toBe(menuSpan);
    expect(issueTree.contains(generatorArea)).toBe(true);
    expect(generatorArea.style.display).toBe("none");

    cleanup.removeRegisteredListeners();
    issueTree.remove();
    menuSpan.remove();
    generatorArea.remove();
  });

  it("does nothing when #issue_tree > .contextual is absent", async () => {
    const menuSpan = document.createElement("span");
    menuSpan.id = "ai-helper-subissuer-generator-menu";
    document.body.appendChild(menuSpan);

    const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_sub_issues");

    expect(document.body.contains(menuSpan)).toBe(true);
    cleanup.removeRegisteredListeners();
    menuSpan.remove();
  });
});
