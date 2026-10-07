import { afterEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";

// T057: characterization tests for ai_helper_settings/index.html.erb extraction.
//
// T060 removed the file's only jQuery usage (research.md decision), so this
// suite drives behavior through plain DOM APIs and fetch instead of jQuery
// mocks. The observable behavior asserted (visibility toggles, AJAX URL,
// script-executing AJAX injection) is unchanged from before the jQuery
// removal; only the mocking mechanics changed, per FR-007b.

describe("initAiHelperSettingsPage", () => {
  let container;

  function addMarkup(config = {}) {
    container = document.createElement("div");
    container.id = "ai-helper-settings-index";
    container.dataset.config = JSON.stringify({
      modelProfilesPath: "/ai_helper_model_profiles",
      compatibleType: "openai_compatible",
      azureType: "azure_openai",
      userIdSupportedTypes: ["openai", "openai_compatible", "azure_openai"],
      ...config,
    });
    document.body.appendChild(container);

    const tabHidden = document.createElement("input");
    tabHidden.name = "tab";
    container.appendChild(tabHidden);

    const tabsDiv = document.createElement("div");
    tabsDiv.className = "tabs";
    const tabLink = document.createElement("a");
    tabLink.id = "tab-model";
    tabsDiv.appendChild(tabLink);
    container.appendChild(tabsDiv);

    const modelProfileSelect = document.createElement("select");
    modelProfileSelect.id = "ai_helper_setting_model_profile_id";
    container.appendChild(modelProfileSelect);

    const descriptionDiv = document.createElement("div");
    descriptionDiv.id = "ai_helper_model_profile_description";
    container.appendChild(descriptionDiv);

    const modelTypeMeta = document.createElement("div");
    modelTypeMeta.id = "ai_helper_model_type";
    container.appendChild(modelTypeMeta);

    ["ai_helper_setting_use_think_model", "ai_helper_setting_attachment_send_enabled",
      "ai_helper_setting_vector_register_all_projects", "ai_helper_setting_use_vector_model_profile",
      "ai_helper_setting_vector_search_enabled"].forEach((id) => {
      const cb = document.createElement("input");
      cb.type = "checkbox";
      cb.id = id;
      container.appendChild(cb);
    });

    ["ai-helper-think-model-settings", "ai-helper-attachment-settings", "ai-helper-vector-target-projects",
      "ai-helper-vector-model-profile-settings", "ai-helper-vector-search", "ai-helper-send-user-id",
      "ai_helper_dimension", "ai_helper_embedding_url"].forEach((id) => {
      const div = document.createElement("div");
      div.id = id;
      container.appendChild(div);
    });

    const toggleRow = document.getElementById("ai_helper_setting_use_vector_model_profile");
    const parentP = document.createElement("p");
    toggleRow.parentNode.insertBefore(parentP, toggleRow);
    parentP.appendChild(toggleRow);

    return { tabHidden, tabLink, modelProfileSelect, descriptionDiv, modelTypeMeta };
  }

  afterEach(() => {
    container?.remove();
    container = undefined;
    vi.unstubAllGlobals();
    delete window.initAiHelperSettingsPage;
    delete window.modelTypeChanged;
    delete window.setSendUserIdVisible;
  });

  it("syncs the hidden tab field when a tab link is clicked", async () => {
    const { tabHidden, tabLink } = addMarkup();
    await loadScript("assets/javascripts/settings/ai_helper_settings");

    window.initAiHelperSettingsPage();
    tabLink.dispatchEvent(new MouseEvent("click", { bubbles: true }));

    expect(tabHidden.value).toBe("model");
  });

  it("loads the model profile via AJAX (script-executing injection) when a profile is selected on init", async () => {
    const { modelProfileSelect, descriptionDiv } = addMarkup();
    const option = document.createElement("option");
    option.value = "42";
    modelProfileSelect.appendChild(option);
    modelProfileSelect.value = "42";
    let capturedUrl;
    // Mirrors the real _show.html.erb response: content followed by a bridge
    // <script> tag that must be re-executed (plain innerHTML assignment does
    // not run embedded scripts). This must work with no `ai_helper` global in
    // scope -- this admin settings page has no @project, so ai_helper.js
    // (gated by PermissionChecker.module_enabled? in _html_header.html.erb)
    // is never loaded here, unlike project-scoped pages.
    vi.stubGlobal("fetch", vi.fn((url) => {
      capturedUrl = url;
      return Promise.resolve({
        ok: true,
        text: () => Promise.resolve('<p>profile 42</p><script>window.__profile42ScriptRan = true;</script>'),
      });
    }));

    await loadScript("assets/javascripts/settings/ai_helper_settings");
    expect(typeof window.ai_helper).toBe("undefined");
    window.initAiHelperSettingsPage();
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(capturedUrl).toBe("/ai_helper_model_profiles/42");
    expect(descriptionDiv.innerHTML).toContain("<p>profile 42</p>");
    // The bridge script must be re-created as a direct child of document.body
    // (the observable proxy, in jsdom, for "would execute in a real browser"
    // -- jsdom doesn't run dynamically-appended scripts, but a real browser
    // does). This is distinct from the inert <script> left behind inside
    // descriptionDiv by the `innerHTML =` assignment itself, which parses but
    // never executes it.
    const reinjectedScripts = Array.from(document.body.children)
      .filter((el) => el.tagName === "SCRIPT" && el.textContent.includes("__profile42ScriptRan"));
    expect(reinjectedScripts).toHaveLength(1);
  });

  it("shows the localized load-error message in the description when the AJAX request fails", async () => {
    const { modelProfileSelect, descriptionDiv } = addMarkup({ loadErrorMessage: "An error occurred" });
    const option = document.createElement("option");
    option.value = "42";
    modelProfileSelect.appendChild(option);
    modelProfileSelect.value = "42";
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve({ ok: false })));

    await loadScript("assets/javascripts/settings/ai_helper_settings");
    window.initAiHelperSettingsPage();
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(descriptionDiv.textContent).toBe("An error occurred");
  });

  it("clears the description when no profile is selected on init", async () => {
    const { descriptionDiv } = addMarkup();
    descriptionDiv.innerHTML = "stale content";

    await loadScript("assets/javascripts/settings/ai_helper_settings");
    window.initAiHelperSettingsPage();

    expect(descriptionDiv.innerHTML).toBe("");
  });

  it("toggles the think-model settings visibility to match the checkbox", async () => {
    addMarkup();
    const thinkCheckbox = document.getElementById("ai_helper_setting_use_think_model");
    thinkCheckbox.checked = true;
    await loadScript("assets/javascripts/settings/ai_helper_settings");

    window.initAiHelperSettingsPage();

    expect(document.getElementById("ai-helper-think-model-settings").style.display).toBe("");

    thinkCheckbox.checked = false;
    thinkCheckbox.dispatchEvent(new Event("change", { bubbles: true }));
    expect(document.getElementById("ai-helper-think-model-settings").style.display).toBe("none");
  });

  it("toggles the attachment settings visibility to match the checkbox", async () => {
    addMarkup();
    const attachmentCheckbox = document.getElementById("ai_helper_setting_attachment_send_enabled");
    attachmentCheckbox.checked = false;
    await loadScript("assets/javascripts/settings/ai_helper_settings");

    window.initAiHelperSettingsPage();

    expect(document.getElementById("ai-helper-attachment-settings").style.display).toBe("none");
  });

  it("hides the target-projects field when register-all is checked", async () => {
    addMarkup();
    const registerAll = document.getElementById("ai_helper_setting_vector_register_all_projects");
    registerAll.checked = true;
    await loadScript("assets/javascripts/settings/ai_helper_settings");

    window.initAiHelperSettingsPage();

    expect(document.getElementById("ai-helper-vector-target-projects").style.display).toBe("none");
  });

  it("hides the vector model profile toggle row when vector search is disabled", async () => {
    addMarkup();
    await loadScript("assets/javascripts/settings/ai_helper_settings");

    window.initAiHelperSettingsPage();

    const toggleRow = document.getElementById("ai_helper_setting_use_vector_model_profile");
    expect(toggleRow.parentElement.style.display).toBe("none");
    expect(document.getElementById("ai-helper-vector-model-profile-settings").style.display).toBe("none");
  });

  it("shows the vector search section and the model-profile toggle row when vector search is enabled", async () => {
    addMarkup();
    const vectorSearchCheckbox = document.getElementById("ai_helper_setting_vector_search_enabled");
    vectorSearchCheckbox.checked = true;
    await loadScript("assets/javascripts/settings/ai_helper_settings");

    window.initAiHelperSettingsPage();

    expect(document.getElementById("ai-helper-vector-search").style.display).toBe("");
    expect(document.getElementById("ai_helper_setting_use_vector_model_profile").parentElement.style.display).toBe("");
  });

  it("modelTypeChanged shows the dimension field for the compatible type", async () => {
    const { modelTypeMeta } = addMarkup();
    await loadScript("assets/javascripts/settings/ai_helper_settings");
    modelTypeMeta.textContent = "openai_compatible";

    window.modelTypeChanged();

    expect(document.getElementById("ai_helper_dimension").style.display).toBe("");
    expect(document.getElementById("ai_helper_embedding_url").style.display).toBe("none");
  });

  it("modelTypeChanged shows the embedding URL field for the azure type", async () => {
    const { modelTypeMeta } = addMarkup();
    await loadScript("assets/javascripts/settings/ai_helper_settings");
    modelTypeMeta.textContent = "azure_openai";

    window.modelTypeChanged();

    expect(document.getElementById("ai_helper_embedding_url").style.display).toBe("");
    expect(document.getElementById("ai_helper_dimension").style.display).toBe("none");
  });

  it("toggles the send-user-id row only for supported model types", async () => {
    const { modelTypeMeta } = addMarkup();
    await loadScript("assets/javascripts/settings/ai_helper_settings");
    modelTypeMeta.textContent = "azure_openai";

    window.setSendUserIdVisible();

    expect(document.getElementById("ai-helper-send-user-id").style.display).toBe("");
  });

  it("does not show the send-user-id row for unsupported model types", async () => {
    const { modelTypeMeta } = addMarkup();
    await loadScript("assets/javascripts/settings/ai_helper_settings");
    modelTypeMeta.textContent = "anthropic";

    window.setSendUserIdVisible();

    expect(document.getElementById("ai-helper-send-user-id").style.display).toBe("none");
  });

  // Regression test: on the general/vector/channels tabs, #ai_helper_model_type
  // and the model-tab-only visibility divs don't exist (only the model tab's
  // AJAX-loaded partial renders them). The original jQuery code no-op'd on a
  // missing element (`$('#missing').text()` -> ""); the jQuery-removal
  // rewrite (T060) initially replaced this with plain `getElementById(...).textContent`,
  // which throws TypeError on null instead of no-op'ing -- a real behavior
  // regression caught via manual browser verification (T063), fixed by
  // guarding each lookup.
  it("does not throw when the model-tab-only elements are absent (e.g. general tab)", async () => {
    addMarkup();
    document.getElementById("ai_helper_model_type").remove();
    document.getElementById("ai-helper-send-user-id").remove();
    document.getElementById("ai_helper_dimension").remove();
    document.getElementById("ai_helper_embedding_url").remove();
    await loadScript("assets/javascripts/settings/ai_helper_settings");

    expect(() => window.initAiHelperSettingsPage()).not.toThrow();
  });
});

describe("initVectorConnectionTest", () => {
  let container;
  let csrfMeta;
  const config = {
    testConnectionUrl: "/ai_helper_settings/test_vector_connection",
    testConnectionSuccessLabel: "Connection successful",
    testConnectionFailedLabel: "Connection failed",
    loadingLabel: "Loading...",
  };

  function addMarkup() {
    csrfMeta = document.createElement("meta");
    csrfMeta.name = "csrf-token";
    csrfMeta.content = "token123";
    document.head.appendChild(csrfMeta);

    container = document.createElement("form");
    container.innerHTML = `
      <fieldset id="ai-helper-qdrant-connection">
        <input type="text" id="ai_helper_setting_vector_search_uri" value="http://qdrant:6333">
        <input type="text" id="ai_helper_setting_vector_search_api_key" value="k">
        <p id="ai-helper-vector-test-connection">
          <button type="button" id="ai-helper-vector-test-connection-btn">Test</button>
          <span id="ai-helper-vector-test-connection-result"></span>
        </p>
      </fieldset>`;
    container.querySelector("fieldset").dataset.config = JSON.stringify(config);
    document.body.appendChild(container);
    return {
      btn: document.getElementById("ai-helper-vector-test-connection-btn"),
      result: document.getElementById("ai-helper-vector-test-connection-result"),
      uri: document.getElementById("ai_helper_setting_vector_search_uri"),
      key: document.getElementById("ai_helper_setting_vector_search_api_key"),
    };
  }

  function jsonResponse(body) {
    return { json: () => Promise.resolve(body) };
  }

  function flush() {
    return new Promise((resolve) => setTimeout(resolve, 0));
  }

  afterEach(() => {
    container?.remove();
    csrfMeta?.remove();
    container = undefined;
    vi.unstubAllGlobals();
    delete window.initVectorConnectionTest;
  });

  async function setup(fetchImpl) {
    const els = addMarkup();
    const fetchMock = vi.fn(fetchImpl);
    vi.stubGlobal("fetch", fetchMock);
    await loadScript("assets/javascripts/settings/ai_helper_settings");
    window.initVectorConnectionTest();
    return { ...els, fetchMock };
  }

  it("does nothing when the fieldset is absent", async () => {
    await loadScript("assets/javascripts/settings/ai_helper_settings");
    expect(() => window.initVectorConnectionTest()).not.toThrow();
  });

  it("posts the current unsaved values with the CSRF token", async () => {
    const { btn, uri, fetchMock } = await setup(() => Promise.resolve(jsonResponse({ success: true })));
    uri.value = "http://changed:6333";

    btn.click();
    await flush();

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, options] = fetchMock.mock.calls[0];
    expect(url).toBe(config.testConnectionUrl);
    expect(options.method).toBe("POST");
    expect(options.headers["X-CSRF-Token"]).toBe("token123");
    const keys = Array.from(options.body.keys());
    expect(keys.sort()).toEqual(["ai_helper_setting[vector_search_api_key]", "ai_helper_setting[vector_search_uri]"]);
    expect(options.body.get("ai_helper_setting[vector_search_uri]")).toBe("http://changed:6333");
    expect(options.body.get("ai_helper_setting[vector_search_api_key]")).toBe("k");
  });

  it("shows success", async () => {
    const { btn, result } = await setup(() => Promise.resolve(jsonResponse({ success: true })));
    btn.click();
    await flush();
    expect(result.textContent).toBe("Connection successful");
    expect(result.className).toBe("ai-helper-connection-success");
  });

  it("shows the server error on failure", async () => {
    const { btn, result } = await setup(() => Promise.resolve(jsonResponse({ success: false, error: "boom" })));
    btn.click();
    await flush();
    expect(result.textContent).toBe("Connection failed: boom");
    expect(result.className).toBe("ai-helper-connection-failure");
  });

  it("shows the HTTP status when the response is not JSON", async () => {
    const { btn, result } = await setup(() => Promise.resolve({ status: 422, json: () => Promise.reject(new Error("bad json")) }));
    btn.click();
    await flush();
    expect(result.textContent).toBe("Connection failed: HTTP 422");
    expect(result.className).toBe("ai-helper-connection-failure");
  });

  it("shows the error message when fetch rejects", async () => {
    const { btn, result } = await setup(() => Promise.reject(new Error("network down")));
    btn.click();
    await flush();
    expect(result.textContent).toBe("Connection failed: network down");
  });

  it("renders error text safely (no HTML injection)", async () => {
    const payload = "<img src=x onerror=alert(1)>";
    const { btn, result } = await setup(() => Promise.resolve(jsonResponse({ success: false, error: payload })));
    btn.click();
    await flush();
    expect(result.querySelector("img")).toBeNull();
    expect(result.textContent).toBe("Connection failed: " + payload);
  });

  it("uses a non-submitting button", async () => {
    const { btn } = await setup(() => Promise.resolve(jsonResponse({ success: true })));
    const onSubmit = vi.fn((e) => e.preventDefault());
    container.addEventListener("submit", onSubmit);
    expect(btn.type).toBe("button");
    btn.click();
    await flush();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  describe("progress and staleness", () => {
    let resolveFetch;
    const pending = () => new Promise((resolve) => { resolveFetch = resolve; });

    it("disables the button and shows the loading label while running", async () => {
      const { btn, result } = await setup(pending);
      btn.click();
      expect(btn.disabled).toBe(true);
      expect(result.textContent).toBe("Loading...");
      expect(result.className).toBe("");
    });

    it("ignores clicks while a request is running", async () => {
      const { btn, fetchMock } = await setup(pending);
      btn.click();
      btn.click();
      expect(fetchMock).toHaveBeenCalledTimes(1);
    });

    it("re-enables the button after success, failure and fetch errors", async () => {
      const outcomes = [
        () => Promise.resolve(jsonResponse({ success: true })),
        () => Promise.resolve(jsonResponse({ success: false, error: "x" })),
        () => Promise.reject(new Error("net")),
      ];
      let i = 0;
      const { btn } = await setup(() => outcomes[i++]());
      for (let n = 0; n < 3; n++) {
        btn.click();
        await flush();
        expect(btn.disabled).toBe(false);
      }
    });

    it("clears the result when the URI or API key changes", async () => {
      const { btn, result, uri, key } = await setup(() => Promise.resolve(jsonResponse({ success: true })));
      for (const [field, type] of [[uri, "input"], [uri, "change"], [key, "input"], [key, "change"]]) {
        btn.click();
        await flush();
        expect(result.textContent).not.toBe("");
        field.dispatchEvent(new Event(type, { bubbles: true }));
        expect(result.textContent).toBe("");
        expect(result.className).toBe("");
      }
    });

    it("discards the response when the input changed during the request", async () => {
      const { btn, result, uri } = await setup(pending);
      btn.click();
      uri.dispatchEvent(new Event("input", { bubbles: true }));
      resolveFetch(jsonResponse({ success: true }));
      await flush();
      expect(result.textContent).toBe("");
      expect(btn.disabled).toBe(false);
    });

    it("shows only the latest result after a second run", async () => {
      const responses = [{ success: false, error: "first" }, { success: true }];
      let i = 0;
      const { btn, result } = await setup(() => Promise.resolve(jsonResponse(responses[i++])));
      btn.click();
      await flush();
      btn.click();
      await flush();
      expect(result.textContent).toBe("Connection successful");
    });
  });
});
