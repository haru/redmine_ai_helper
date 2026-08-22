import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "./support/load_script.js";

// ai_helper_sub_issues.js is an IIFE with no window-exposed API; it wires up
// DOM event listeners and a MutationObserver on load. We drive it purely
// through DOM events and fetch stubbing.

describe("ai_helper_sub_issues (IIFE)", () => {
  let container;
  let fetchMock;

  beforeEach(() => {
    container = document.createElement("div");
    container.id = "content";
    document.body.appendChild(container);
  });

  afterEach(() => {
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
    if (wrapInDiv) container.appendChild(mountPoint);

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
    await loadScript("assets/javascripts/ai_helper_sub_issues");
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
