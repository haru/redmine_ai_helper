import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";

const SCRIPT = "assets/javascripts/project_health/ai_helper_health_report_editor";

function buildBody({ edited = false } = {}) {
  const wrapper = document.createElement("div");
  wrapper.innerHTML = `
    <div class="ai-helper-health-report-body" data-report-id="7" data-update-url="/update/7">
      <div class="contextual"><a href="#" class="ai-helper-health-report-edit-link">Edit</a></div>
      <div class="ai-helper-health-report-view">
        <div class="ai-helper-health-report-current">current</div>
        ${edited ? '<div class="ai-helper-health-report-original" hidden>orig</div>' : ""}
      </div>
      ${edited ? '<a href="#" class="ai-helper-health-report-show-original">orig</a><a href="#" class="ai-helper-health-report-show-current" hidden>cur</a>' : ""}
      <form class="ai-helper-health-report-edit-form" hidden>
        <div class="ai-helper-health-report-edit-errors" hidden></div>
        <textarea data-help-url="/help" data-preview-url="/preview">body</textarea>
        <input type="submit" value="Save">
        <a href="#" class="ai-helper-health-report-edit-cancel">Cancel</a>
      </form>
    </div>
    <table><tr data-report-id="7"><td><span class="ai-helper-health-report-edited-marker" hidden></span></td></tr></table>`;
  document.body.appendChild(wrapper);
  return wrapper;
}

const click = (el) => el.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("ai_helper_health_report_editor", () => {
  let wrapper;
  let added;
  let realAdd;

  beforeEach(async () => {
    delete window.aiHelperHealthReportEditorLoaded;
    added = [];
    realAdd = document.addEventListener.bind(document);
    vi.spyOn(document, "addEventListener").mockImplementation((type, fn, opts) => {
      added.push([type, fn]);
      realAdd(type, fn, opts);
    });
    const meta = document.createElement("meta");
    meta.name = "csrf-token";
    meta.content = "tok";
    document.head.appendChild(meta);
    await loadScript(SCRIPT);
  });

  afterEach(() => {
    added.forEach(([type, fn]) => document.removeEventListener(type, fn));
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    wrapper?.remove();
    document.querySelectorAll('meta[name="csrf-token"]').forEach((m) => m.remove());
    delete window.jsToolBar;
  });

  it("does not register listeners twice when loaded again", async () => {
    const count = added.length;
    await loadScript(SCRIPT);
    expect(added.length).toBe(count);
  });

  it("shows the form and builds the toolbar once, then cancel restores the view", () => {
    const toolbar = { setHelpLink: vi.fn(), setPreviewUrl: vi.fn(), draw: vi.fn() };
    window.jsToolBar = vi.fn(function () { return toolbar; });
    wrapper = buildBody();
    const link = wrapper.querySelector(".ai-helper-health-report-edit-link");
    const form = wrapper.querySelector("form");

    click(link);
    expect(form.hidden).toBe(false);
    expect(link.hidden).toBe(true);
    expect(wrapper.querySelector(".ai-helper-health-report-view").hidden).toBe(true);
    expect(toolbar.setHelpLink).toHaveBeenCalledWith("/help");
    expect(toolbar.setPreviewUrl).toHaveBeenCalledWith("/preview");
    expect(toolbar.draw).toHaveBeenCalledTimes(1);

    wrapper.querySelector("textarea").value = "changed";
    click(wrapper.querySelector(".ai-helper-health-report-edit-cancel"));
    expect(wrapper.querySelector("textarea").value).toBe("body");
    expect(form.hidden).toBe(true);
    expect(link.hidden).toBe(false);
    expect(wrapper.querySelector(".ai-helper-health-report-view").hidden).toBe(false);

    click(link);
    expect(window.jsToolBar).toHaveBeenCalledTimes(1);
  });

  it("works without jsToolBar", () => {
    wrapper = buildBody();
    click(wrapper.querySelector(".ai-helper-health-report-edit-link"));
    expect(wrapper.querySelector("form").hidden).toBe(false);
  });

  it("toggles between the edited and original content", () => {
    wrapper = buildBody({ edited: true });
    click(wrapper.querySelector(".ai-helper-health-report-show-original"));
    expect(wrapper.querySelector(".ai-helper-health-report-current").hidden).toBe(true);
    expect(wrapper.querySelector(".ai-helper-health-report-original").hidden).toBe(false);
    expect(wrapper.querySelector(".ai-helper-health-report-show-current").hidden).toBe(false);
    click(wrapper.querySelector(".ai-helper-health-report-show-current"));
    expect(wrapper.querySelector(".ai-helper-health-report-current").hidden).toBe(false);
    expect(wrapper.querySelector(".ai-helper-health-report-original").hidden).toBe(true);
  });

  it("replaces the body and reveals the history marker on successful save", async () => {
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({ status: "ok", edited: true, html: '<div class="ai-helper-health-report-body" data-report-id="7">new</div>' }),
    })));
    wrapper = buildBody();
    wrapper.querySelector("form").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await flush();

    expect(fetch).toHaveBeenCalledWith("/update/7", expect.objectContaining({ method: "PATCH" }));
    expect(fetch.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("tok");
    expect(wrapper.querySelector(".ai-helper-health-report-body").textContent).toBe("new");
    expect(wrapper.querySelector(".ai-helper-health-report-edited-marker").hidden).toBe(false);
  });

  it("keeps the marker hidden when nothing changed", async () => {
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({ status: "ok", edited: false, html: '<div class="ai-helper-health-report-body" data-report-id="7">same</div>' }),
    })));
    wrapper = buildBody();
    wrapper.querySelector("form").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await flush();

    expect(wrapper.querySelector(".ai-helper-health-report-edited-marker").hidden).toBe(true);
  });

  it("shows server errors as text and keeps the form", async () => {
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve({
      ok: false,
      json: () => Promise.resolve({ status: "error", errors: ["<b>bad</b>"] }),
    })));
    wrapper = buildBody();
    const form = wrapper.querySelector("form");
    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await flush();

    const box = wrapper.querySelector(".ai-helper-health-report-edit-errors");
    expect(box.hidden).toBe(false);
    expect(box.querySelector("li").textContent).toBe("<b>bad</b>");
    expect(box.querySelector("b")).toBeNull();
    expect(wrapper.contains(form)).toBe(true);
  });

  it("shows an error list when the response has no errors array", async () => {
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve({ ok: false, json: () => Promise.resolve({}) })));
    wrapper = buildBody();
    wrapper.querySelector("form").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await flush();

    expect(wrapper.querySelector(".ai-helper-health-report-edit-errors").hidden).toBe(false);
  });

  it("shows the network error message when fetch rejects", async () => {
    vi.stubGlobal("fetch", vi.fn(() => Promise.reject(new Error("offline"))));
    wrapper = buildBody();
    wrapper.querySelector("form").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await flush();

    expect(wrapper.querySelector(".ai-helper-health-report-edit-errors").textContent).toBe("offline");
  });

  it("ignores unrelated clicks and submits", () => {
    wrapper = buildBody();
    click(wrapper.querySelector(".ai-helper-health-report-current"));
    const other = document.createElement("form");
    wrapper.appendChild(other);
    other.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    expect(wrapper.querySelector("form.ai-helper-health-report-edit-form").hidden).toBe(true);
  });
});
