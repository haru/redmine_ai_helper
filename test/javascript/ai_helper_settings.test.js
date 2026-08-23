import { afterEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "./support/load_script.js";

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
    await loadScript("assets/javascripts/ai_helper_settings");

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

    await loadScript("assets/javascripts/ai_helper_settings");
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

    await loadScript("assets/javascripts/ai_helper_settings");
    window.initAiHelperSettingsPage();
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(descriptionDiv.textContent).toBe("An error occurred");
  });

  it("clears the description when no profile is selected on init", async () => {
    const { descriptionDiv } = addMarkup();
    descriptionDiv.innerHTML = "stale content";

    await loadScript("assets/javascripts/ai_helper_settings");
    window.initAiHelperSettingsPage();

    expect(descriptionDiv.innerHTML).toBe("");
  });

  it("toggles the think-model settings visibility to match the checkbox", async () => {
    addMarkup();
    const thinkCheckbox = document.getElementById("ai_helper_setting_use_think_model");
    thinkCheckbox.checked = true;
    await loadScript("assets/javascripts/ai_helper_settings");

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
    await loadScript("assets/javascripts/ai_helper_settings");

    window.initAiHelperSettingsPage();

    expect(document.getElementById("ai-helper-attachment-settings").style.display).toBe("none");
  });

  it("hides the target-projects field when register-all is checked", async () => {
    addMarkup();
    const registerAll = document.getElementById("ai_helper_setting_vector_register_all_projects");
    registerAll.checked = true;
    await loadScript("assets/javascripts/ai_helper_settings");

    window.initAiHelperSettingsPage();

    expect(document.getElementById("ai-helper-vector-target-projects").style.display).toBe("none");
  });

  it("hides the vector model profile toggle row when vector search is disabled", async () => {
    addMarkup();
    await loadScript("assets/javascripts/ai_helper_settings");

    window.initAiHelperSettingsPage();

    const toggleRow = document.getElementById("ai_helper_setting_use_vector_model_profile");
    expect(toggleRow.parentElement.style.display).toBe("none");
    expect(document.getElementById("ai-helper-vector-model-profile-settings").style.display).toBe("none");
  });

  it("shows the vector search section and the model-profile toggle row when vector search is enabled", async () => {
    addMarkup();
    const vectorSearchCheckbox = document.getElementById("ai_helper_setting_vector_search_enabled");
    vectorSearchCheckbox.checked = true;
    await loadScript("assets/javascripts/ai_helper_settings");

    window.initAiHelperSettingsPage();

    expect(document.getElementById("ai-helper-vector-search").style.display).toBe("");
    expect(document.getElementById("ai_helper_setting_use_vector_model_profile").parentElement.style.display).toBe("");
  });

  it("modelTypeChanged shows the dimension field for the compatible type", async () => {
    const { modelTypeMeta } = addMarkup();
    await loadScript("assets/javascripts/ai_helper_settings");
    modelTypeMeta.textContent = "openai_compatible";

    window.modelTypeChanged();

    expect(document.getElementById("ai_helper_dimension").style.display).toBe("");
    expect(document.getElementById("ai_helper_embedding_url").style.display).toBe("none");
  });

  it("modelTypeChanged shows the embedding URL field for the azure type", async () => {
    const { modelTypeMeta } = addMarkup();
    await loadScript("assets/javascripts/ai_helper_settings");
    modelTypeMeta.textContent = "azure_openai";

    window.modelTypeChanged();

    expect(document.getElementById("ai_helper_embedding_url").style.display).toBe("");
    expect(document.getElementById("ai_helper_dimension").style.display).toBe("none");
  });

  it("toggles the send-user-id row only for supported model types", async () => {
    const { modelTypeMeta } = addMarkup();
    await loadScript("assets/javascripts/ai_helper_settings");
    modelTypeMeta.textContent = "azure_openai";

    window.setSendUserIdVisible();

    expect(document.getElementById("ai-helper-send-user-id").style.display).toBe("");
  });

  it("does not show the send-user-id row for unsupported model types", async () => {
    const { modelTypeMeta } = addMarkup();
    await loadScript("assets/javascripts/ai_helper_settings");
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
    await loadScript("assets/javascripts/ai_helper_settings");

    expect(() => window.initAiHelperSettingsPage()).not.toThrow();
  });
});
