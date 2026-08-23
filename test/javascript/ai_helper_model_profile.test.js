import { afterEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "./support/load_script.js";

// T056: characterization tests for ai_helper_model_profiles/_show.html.erb
// (T051) and _form.html.erb (T052) extraction.

describe("AiHelperModelProfile.initShow (from _show.html.erb)", () => {
  let dialog;
  let meta;

  function addShowMarkup(config = {}) {
    dialog = document.createElement("dialog");
    dialog.id = "copy-profile-dialog";
    dialog.showModal = vi.fn();
    dialog.close = vi.fn();
    dialog.dataset.config = JSON.stringify({
      copyUrl: "/ai_helper_model_profiles/1/copy",
      redirectUrl: "/ai_helper_setting?tab=model",
      ...config,
    });
    document.body.appendChild(dialog);

    const nameInput = document.createElement("input");
    nameInput.id = "new-profile-name";
    dialog.appendChild(nameInput);

    const submitBtn = document.createElement("button");
    submitBtn.id = "copy-profile-submit";
    dialog.appendChild(submitBtn);

    const cancelBtn = document.createElement("a");
    cancelBtn.id = "copy-profile-cancel";
    dialog.appendChild(cancelBtn);

    const errorEl = document.createElement("p");
    errorEl.id = "copy-profile-error";
    errorEl.style.display = "none";
    dialog.appendChild(errorEl);

    const copyBtn = document.createElement("a");
    copyBtn.id = "copy-model-profile-btn";
    document.body.appendChild(copyBtn);

    meta = document.createElement("meta");
    meta.name = "csrf-token";
    meta.content = "test-csrf-token";
    document.head.appendChild(meta);

    return { dialog, nameInput, submitBtn, cancelBtn, errorEl, copyBtn };
  }

  afterEach(() => {
    dialog?.remove();
    document.getElementById("copy-model-profile-btn")?.remove();
    meta?.remove();
    dialog = undefined;
    meta = undefined;
    vi.unstubAllGlobals();
    delete window.AiHelperModelProfile;
  });

  it("opens the dialog and focuses the name input when the copy button is clicked", async () => {
    const { copyBtn, nameInput, dialog: dlg, errorEl } = addShowMarkup();
    nameInput.value = "stale";
    errorEl.style.display = "block";
    const focusSpy = vi.spyOn(nameInput, "focus");
    await loadScript("assets/javascripts/ai_helper_model_profile");

    window.AiHelperModelProfile.initShow();
    copyBtn.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    expect(dlg.showModal).toHaveBeenCalled();
    expect(nameInput.value).toBe("");
    expect(errorEl.style.display).toBe("none");
    expect(focusSpy).toHaveBeenCalled();
  });

  it("submits the trimmed name and redirects on success", async () => {
    const { submitBtn, nameInput } = addShowMarkup({ copyUrl: "/copy-url", redirectUrl: "/redirect-url" });
    nameInput.value = "  New Profile  ";
    let capturedUrl;
    let capturedOptions;
    vi.stubGlobal("fetch", vi.fn((url, options) => {
      capturedUrl = url;
      capturedOptions = options;
      return Promise.resolve({
        headers: { get: () => "application/json" },
        json: () => Promise.resolve({ success: true }),
      });
    }));
    delete window.location;
    window.location = { href: "" };

    await loadScript("assets/javascripts/ai_helper_model_profile");
    window.AiHelperModelProfile.initShow();
    submitBtn.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(capturedUrl).toBe("/copy-url");
    expect(capturedOptions.method).toBe("POST");
    expect(capturedOptions.headers["X-CSRF-Token"]).toBe("test-csrf-token");
    expect(capturedOptions.body).toBe("name=" + encodeURIComponent("New Profile"));
    expect(window.location.href).toBe("/redirect-url");
  });

  it("shows validation errors on failure instead of redirecting", async () => {
    const { submitBtn, errorEl } = addShowMarkup();
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve({
      headers: { get: () => "application/json" },
      json: () => Promise.resolve({ success: false, errors: ["Name is required"] }),
    })));

    await loadScript("assets/javascripts/ai_helper_model_profile");
    window.AiHelperModelProfile.initShow();
    submitBtn.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(errorEl.textContent).toBe("Name is required");
    expect(errorEl.style.display).toBe("block");
  });

  it("shows the response's error message when the server does not return JSON", async () => {
    const { submitBtn, errorEl } = addShowMarkup();
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve({
      headers: { get: () => "text/html" },
      statusText: "Internal Server Error",
      text: () => Promise.resolve("<html>oops</html>"),
    })));

    await loadScript("assets/javascripts/ai_helper_model_profile");
    window.AiHelperModelProfile.initShow();
    submitBtn.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(errorEl.textContent).toBe("Internal Server Error");
    expect(errorEl.style.display).toBe("block");
  });

  it("closes the dialog when cancel is clicked", async () => {
    const { cancelBtn, dialog: dlg } = addShowMarkup();
    await loadScript("assets/javascripts/ai_helper_model_profile");
    window.AiHelperModelProfile.initShow();

    cancelBtn.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    expect(dlg.close).toHaveBeenCalled();
  });

  it("submits via Enter key in the name input", async () => {
    const { nameInput, submitBtn } = addShowMarkup();
    const clickSpy = vi.spyOn(submitBtn, "click");
    await loadScript("assets/javascripts/ai_helper_model_profile");
    window.AiHelperModelProfile.initShow();

    nameInput.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }));

    expect(clickSpy).toHaveBeenCalled();
  });

  it("does nothing when the dialog is absent", async () => {
    await loadScript("assets/javascripts/ai_helper_model_profile");
    expect(() => window.AiHelperModelProfile.initShow()).not.toThrow();
  });
});

describe("AiHelperModelProfile.initForm (from _form.html.erb)", () => {
  let container;

  function addFormMarkup(config = {}) {
    container = document.createElement("div");
    container.id = "ai-helper-model-profile-form";
    container.dataset.config = JSON.stringify({
      compatibleType: "openai_compatible",
      azureType: "azure_openai",
      openaiType: "openai",
      testConnectionUrl: "/test-connection",
      testConnectionFailedLabel: "Failed",
      testConnectionSuccessLabel: "Success",
      ...config,
    });
    document.body.appendChild(container);

    const llmTypeSelect = document.createElement("select");
    llmTypeSelect.id = "ai_helper_model_profile_llm_type";
    ["openai", "openai_compatible", "azure_openai", "anthropic"].forEach((v) => {
      const opt = document.createElement("option");
      opt.value = v;
      llmTypeSelect.appendChild(opt);
    });
    container.appendChild(llmTypeSelect);

    const baseUriElement = document.createElement("p");
    baseUriElement.id = "ai-helper-model-base-uri";
    container.appendChild(baseUriElement);

    const accessKeyWrapper = document.createElement("p");
    accessKeyWrapper.id = "ai-helper-mode-access-key";
    const requiredSpan = document.createElement("span");
    requiredSpan.className = "required";
    accessKeyWrapper.appendChild(requiredSpan);
    container.appendChild(accessKeyWrapper);

    const organizationIdElement = document.createElement("p");
    organizationIdElement.id = "ai-helper-model-organization-id";
    container.appendChild(organizationIdElement);

    return { llmTypeSelect, baseUriElement, requiredSpan, organizationIdElement };
  }

  afterEach(() => {
    container?.remove();
    container = undefined;
    vi.unstubAllGlobals();
    delete window.AiHelperModelProfile;
  });

  it("shows the base URI field for the compatible type and hides it otherwise", async () => {
    const { llmTypeSelect, baseUriElement } = addFormMarkup();
    llmTypeSelect.value = "openai_compatible";
    await loadScript("assets/javascripts/ai_helper_model_profile");
    window.AiHelperModelProfile.initForm();

    expect(baseUriElement.style.display).toBe("block");

    llmTypeSelect.value = "openai";
    llmTypeSelect.dispatchEvent(new Event("change", { bubbles: true }));
    expect(baseUriElement.style.display).toBe("none");
  });

  it("shows the base URI field for the azure type", async () => {
    const { llmTypeSelect, baseUriElement } = addFormMarkup();
    llmTypeSelect.value = "azure_openai";
    await loadScript("assets/javascripts/ai_helper_model_profile");
    window.AiHelperModelProfile.initForm();

    expect(baseUriElement.style.display).toBe("block");
  });

  it("hides the required marker on the access key for the compatible type only", async () => {
    const { llmTypeSelect, requiredSpan } = addFormMarkup();
    llmTypeSelect.value = "openai_compatible";
    await loadScript("assets/javascripts/ai_helper_model_profile");
    window.AiHelperModelProfile.initForm();

    expect(requiredSpan.style.display).toBe("none");

    llmTypeSelect.value = "openai";
    llmTypeSelect.dispatchEvent(new Event("change", { bubbles: true }));
    expect(requiredSpan.style.display).toBe("block");
  });

  it("shows the organization ID field for the openai type only", async () => {
    const { llmTypeSelect, organizationIdElement } = addFormMarkup();
    llmTypeSelect.value = "openai";
    await loadScript("assets/javascripts/ai_helper_model_profile");
    window.AiHelperModelProfile.initForm();

    expect(organizationIdElement.style.display).toBe("block");

    llmTypeSelect.value = "anthropic";
    llmTypeSelect.dispatchEvent(new Event("change", { bubbles: true }));
    expect(organizationIdElement.style.display).toBe("none");
  });

  it("clears the readonly attribute on the access key/organization fields on focus", async () => {
    addFormMarkup();
    const accessKeyInput = document.createElement("input");
    accessKeyInput.id = "ai_helper_model_profile_access_key";
    accessKeyInput.setAttribute("readonly", "readonly");
    container.appendChild(accessKeyInput);

    await loadScript("assets/javascripts/ai_helper_model_profile");
    window.AiHelperModelProfile.initForm();

    accessKeyInput.dispatchEvent(new Event("focus"));
    expect(accessKeyInput.hasAttribute("readonly")).toBe(false);
  });

  describe("connection test button", () => {
    function addTestConnectionMarkup() {
      const form = document.createElement("form");
      container.appendChild(form);
      const btn = document.createElement("button");
      btn.id = "ai-helper-test-connection-btn";
      form.appendChild(btn);
      const result = document.createElement("span");
      result.id = "ai-helper-test-connection-result";
      form.appendChild(result);
      const meta = document.createElement("meta");
      meta.name = "csrf-token";
      meta.content = "csrf-token-value";
      document.head.appendChild(meta);
      return { form, btn, result, meta };
    }

    it("shows the success label when the connection test succeeds", async () => {
      addFormMarkup();
      const { btn, result, meta } = addTestConnectionMarkup();
      vi.stubGlobal("fetch", vi.fn(() => Promise.resolve({
        headers: { get: () => "application/json" },
        json: () => Promise.resolve({ success: true }),
      })));

      await loadScript("assets/javascripts/ai_helper_model_profile");
      window.AiHelperModelProfile.initForm();
      btn.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(result.textContent).toBe("Success");
      expect(result.className).toBe("ai-helper-connection-success");
      expect(btn.disabled).toBe(false);
      meta.remove();
    });

    it("shows the failure label with the server error when the connection test fails", async () => {
      addFormMarkup();
      const { btn, result, meta } = addTestConnectionMarkup();
      vi.stubGlobal("fetch", vi.fn(() => Promise.resolve({
        headers: { get: () => "application/json" },
        json: () => Promise.resolve({ success: false, error: "bad key" }),
      })));

      await loadScript("assets/javascripts/ai_helper_model_profile");
      window.AiHelperModelProfile.initForm();
      btn.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(result.textContent).toBe("Failed: bad key");
      expect(result.className).toBe("ai-helper-connection-failure");
      meta.remove();
    });

    it("shows the failure label when the server does not return JSON", async () => {
      addFormMarkup();
      const { btn, result, meta } = addTestConnectionMarkup();
      vi.stubGlobal("fetch", vi.fn(() => Promise.resolve({
        headers: { get: () => "text/html" },
        text: () => Promise.resolve("<html>oops</html>"),
      })));

      await loadScript("assets/javascripts/ai_helper_model_profile");
      window.AiHelperModelProfile.initForm();
      btn.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(result.textContent).toBe("Failed: Failed");
      expect(result.className).toBe("ai-helper-connection-failure");
      expect(btn.disabled).toBe(false);
      meta.remove();
    });

    it("shows the failure label with the error message when the fetch request itself fails", async () => {
      addFormMarkup();
      const { btn, result, meta } = addTestConnectionMarkup();
      vi.stubGlobal("fetch", vi.fn(() => Promise.reject(new Error("network down"))));

      await loadScript("assets/javascripts/ai_helper_model_profile");
      window.AiHelperModelProfile.initForm();
      btn.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(result.textContent).toBe("Failed: network down");
      expect(result.className).toBe("ai-helper-connection-failure");
      expect(btn.disabled).toBe(false);
      meta.remove();
    });

    it("clears the result text when any form field changes", async () => {
      addFormMarkup();
      const { form, result, meta } = addTestConnectionMarkup();
      const field = document.createElement("input");
      form.appendChild(field);
      result.textContent = "previous result";

      await loadScript("assets/javascripts/ai_helper_model_profile");
      window.AiHelperModelProfile.initForm();
      field.dispatchEvent(new Event("input", { bubbles: true }));

      expect(result.textContent).toBe("");
      meta.remove();
    });
  });

  it("does nothing when the form container is absent", async () => {
    await loadScript("assets/javascripts/ai_helper_model_profile");
    expect(() => window.AiHelperModelProfile.initForm()).not.toThrow();
  });
});
