import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScriptAndFireDOMContentLoaded } from "./support/dom_content_loaded.js";
import { loadScript } from "./support/load_script.js";

// Ported from the pre-existing (never-run) test/javascript/ai_helper_chat_settings_test.js.
// These cover two fixes:
//   1. syncHiddenInput must match datalist options by their `value` (the user
//      name, what the browser actually writes into the text input when a
//      suggestion is picked) and copy the id from `data-user-id`.
//   2. setupBindingFormIsolation must disable every other adapter's
//      "add binding" fields before a submit so same-named fields from other
//      adapters are not sent along with the clicked adapter's binding.
//
// The setup functions are called explicitly (rather than relying on the
// file's own DOMContentLoaded listener) because the DOM fixtures used here
// are built after the script is loaded.

describe("ai_helper_chat_settings.js", () => {
  let container;

  beforeEach(async () => {
    await loadScript("assets/javascripts/ai_helper_chat_settings");
  });

  afterEach(() => {
    if (container) {container.remove();}
    container = undefined;
    vi.unstubAllGlobals();
  });

  function createDatalistDOM(channelType, users) {
    container = document.createElement("div");

    const textInput = document.createElement("input");
    textInput.setAttribute("list", `ai-helper-users-datalist-${channelType}`);
    container.appendChild(textInput);

    const hiddenInput = document.createElement("input");
    hiddenInput.type = "hidden";
    hiddenInput.name = `chat_adapter_settings[${channelType}][redmine_user_id]`;
    container.appendChild(hiddenInput);

    const datalist = document.createElement("datalist");
    datalist.id = `ai-helper-users-datalist-${channelType}`;
    users.forEach(function (user) {
      const option = document.createElement("option");
      option.setAttribute("value", user.name);
      option.setAttribute("data-user-id", String(user.id));
      datalist.appendChild(option);
    });
    container.appendChild(datalist);

    document.body.appendChild(container);
    return { textInput, hiddenInput };
  }

  it("selecting an option by its name value resolves the correct user id", () => {
    const { textInput, hiddenInput } = createDatalistDOM("ui_chat", [
      { id: 3, name: "Dave Lopper" },
      { id: 7, name: "Redmine Admin" },
    ]);
    window.setupDatalistHandlers();

    textInput.value = "Dave Lopper";
    textInput.dispatchEvent(new Event("input", { bubbles: true }));

    expect(hiddenInput.value).toBe("3");
  });

  it("clears the hidden user id when the text does not match any option", () => {
    const { textInput, hiddenInput } = createDatalistDOM("ui_chat", [
      { id: 3, name: "Dave Lopper" },
    ]);
    window.setupDatalistHandlers();

    textInput.value = "Someone Else";
    textInput.dispatchEvent(new Event("input", { bubbles: true }));

    expect(hiddenInput.value).toBe("");
  });

  function createBindingFieldsets(channelTypes) {
    container = document.createElement("div");
    const fieldsets = {};

    channelTypes.forEach(function (channelType) {
      const fieldset = document.createElement("fieldset");
      fieldset.id = `adapter-bindings-${channelType}`;

      const channelTypeInput = document.createElement("input");
      channelTypeInput.type = "hidden";
      channelTypeInput.name = "ai_helper_channel_binding[channel_type]";
      channelTypeInput.value = channelType;
      fieldset.appendChild(channelTypeInput);

      const channelIdInput = document.createElement("input");
      channelIdInput.type = "text";
      channelIdInput.name = "ai_helper_channel_binding[channel_id]";
      fieldset.appendChild(channelIdInput);

      const submitButton = document.createElement("input");
      submitButton.type = "submit";
      submitButton.setAttribute("formaction", "/ai_helper_channel_bindings");
      fieldset.appendChild(submitButton);

      container.appendChild(fieldset);
      fieldsets[channelType] = { fieldset, channelTypeInput, channelIdInput, submitButton };
    });

    document.body.appendChild(container);
    return fieldsets;
  }

  it("clicking an adapter's add-binding button isolates its fields", () => {
    const fieldsets = createBindingFieldsets(["ui_chat", "fake_other"]);
    window.setupBindingFormIsolation();

    fieldsets.ui_chat.submitButton.click();

    expect(fieldsets.ui_chat.channelIdInput.disabled).toBe(false);
    expect(fieldsets.fake_other.channelIdInput.disabled).toBe(true);
    expect(fieldsets.fake_other.channelTypeInput.disabled).toBe(true);
  });

  it("switching the clicked adapter re-isolates fields correctly", () => {
    const fieldsets = createBindingFieldsets(["ui_chat", "fake_other"]);
    window.setupBindingFormIsolation();

    fieldsets.ui_chat.submitButton.click();
    fieldsets.fake_other.submitButton.click();

    expect(fieldsets.fake_other.channelIdInput.disabled).toBe(false);
    expect(fieldsets.ui_chat.channelIdInput.disabled).toBe(true);
  });

  function createAdapterVisibilityDOM(channelType, { checked = false, withBindings = true } = {}) {
    container = document.createElement("div");

    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.className = "adapter-enabled-checkbox";
    checkbox.setAttribute("data-adapter-type", channelType);
    checkbox.checked = checked;
    container.appendChild(checkbox);

    const settingsDiv = document.createElement("div");
    settingsDiv.id = `adapter-settings-${channelType}`;
    container.appendChild(settingsDiv);

    let bindingsFieldset;
    if (withBindings) {
      bindingsFieldset = document.createElement("fieldset");
      bindingsFieldset.id = `adapter-bindings-${channelType}`;
      container.appendChild(bindingsFieldset);
    }

    document.body.appendChild(container);
    return { checkbox, settingsDiv, bindingsFieldset };
  }

  describe("setAdapterSettingsVisible", () => {
    it("shows the settings and bindings when the checkbox is checked", () => {
      const { settingsDiv, bindingsFieldset } = createAdapterVisibilityDOM("ui_chat", { checked: true });

      window.setAdapterSettingsVisible("ui_chat");

      expect(settingsDiv.style.display).toBe("");
      expect(bindingsFieldset.style.display).toBe("");
    });

    it("hides the settings and bindings when the checkbox is unchecked", () => {
      const { settingsDiv, bindingsFieldset } = createAdapterVisibilityDOM("ui_chat", { checked: false });

      window.setAdapterSettingsVisible("ui_chat");

      expect(settingsDiv.style.display).toBe("none");
      expect(bindingsFieldset.style.display).toBe("none");
    });

    it("does nothing when the bindings fieldset has not been rendered yet", () => {
      const { settingsDiv } = createAdapterVisibilityDOM("ui_chat", { checked: true, withBindings: false });

      expect(() => window.setAdapterSettingsVisible("ui_chat")).not.toThrow();
      expect(settingsDiv.style.display).toBe("");
    });

    it("does nothing when the checkbox or settings div is missing", () => {
      expect(() => window.setAdapterSettingsVisible("missing_type")).not.toThrow();
    });
  });

  describe("setupAdapterCheckboxListeners", () => {
    it("returns the adapter types found and toggles visibility on change", () => {
      const { checkbox, settingsDiv } = createAdapterVisibilityDOM("ui_chat", { checked: false });

      const types = window.setupAdapterCheckboxListeners();
      expect(types).toEqual(["ui_chat"]);

      checkbox.checked = true;
      checkbox.dispatchEvent(new Event("change", { bubbles: true }));

      expect(settingsDiv.style.display).toBe("");
    });

    it("skips checkboxes without a data-adapter-type attribute", () => {
      container = document.createElement("div");
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.className = "adapter-enabled-checkbox";
      container.appendChild(checkbox);
      document.body.appendChild(container);

      const types = window.setupAdapterCheckboxListeners();

      expect(types).toEqual([]);
    });
  });

  describe("setupDatalistHandlers additional branches", () => {
    it("syncs on blur as well as input", () => {
      const { textInput, hiddenInput } = createDatalistDOM("ui_chat", [{ id: 3, name: "Dave Lopper" }]);
      window.setupDatalistHandlers();

      textInput.value = "Dave Lopper";
      textInput.dispatchEvent(new Event("blur", { bubbles: true }));

      expect(hiddenInput.value).toBe("3");
    });

    it("does nothing when there is no matching hidden input for the channel type", () => {
      container = document.createElement("div");
      const textInput = document.createElement("input");
      textInput.setAttribute("list", "ai-helper-users-datalist-orphan_type");
      container.appendChild(textInput);
      document.body.appendChild(container);

      expect(() => window.setupDatalistHandlers()).not.toThrow();
      expect(() =>
        textInput.dispatchEvent(new Event("input", { bubbles: true })),
      ).not.toThrow();
    });

    it("does nothing when the referenced datalist element is absent", () => {
      const { textInput, hiddenInput } = createDatalistDOM("ui_chat", []);
      document.getElementById("ai-helper-users-datalist-ui_chat").remove();
      window.setupDatalistHandlers();

      textInput.value = "anything";
      expect(() => textInput.dispatchEvent(new Event("input", { bubbles: true }))).not.toThrow();
      expect(hiddenInput.value).toBe("");
    });
  });

  function createHelpDialog(channelType, { open = false, bodyHtml = "" } = {}) {
    container = document.createElement("div");

    const link = document.createElement("a");
    link.className = "adapter-help-trigger";
    link.href = `/ai_helper/adapter_help/${channelType}`;
    link.setAttribute("data-channel-type", channelType);
    container.appendChild(link);

    const dialog = document.createElement("dialog");
    dialog.id = `adapter-help-dialog-${channelType}`;
    dialog.className = "adapter-help-dialog";
    if (open) {dialog.setAttribute("open", "");}

    const header = document.createElement("div");
    header.className = "adapter-help-dialog-header";
    dialog.appendChild(header);

    const closeBtn = document.createElement("button");
    closeBtn.className = "adapter-help-dialog-close";
    header.appendChild(closeBtn);

    const body = document.createElement("div");
    body.className = "adapter-help-dialog-body";
    body.innerHTML = bodyHtml;
    dialog.appendChild(body);

    container.appendChild(dialog);
    document.body.appendChild(container);

    dialog.show = vi.fn(function () {
      this.open = true;
    });
    dialog.close = vi.fn(function () {
      this.open = false;
    });
    dialog.getBoundingClientRect = () => ({ top: 0, left: 0, right: 0, bottom: 0, width: 200, height: 100 });
    link.getBoundingClientRect = () => ({ top: 10, left: 10, right: 30, bottom: 30, width: 20, height: 20 });

    return { link, dialog, header, closeBtn, body };
  }

  describe("setupHelpDialogListeners", () => {
    it("fetches and fills the dialog body on first open, then shows and positions it", async () => {
      const { link, dialog, body } = createHelpDialog("ui_chat");
      const fetchMock = vi.fn(async () => ({ ok: true, text: async () => "<p>Help text</p>" }));
      vi.stubGlobal("fetch", fetchMock);
      window.setupHelpDialogListeners();

      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(fetchMock).toHaveBeenCalledWith("/ai_helper/adapter_help/ui_chat");
      expect(body.innerHTML).toContain("Help text");
      expect(dialog.show).toHaveBeenCalledTimes(1);
      expect(dialog.style.top).toBeTruthy();
    });

    it("does not fetch again when the dialog body already has content", async () => {
      const { link } = createHelpDialog("ui_chat", { bodyHtml: "<p>Already loaded</p>" });
      const fetchMock = vi.fn();
      vi.stubGlobal("fetch", fetchMock);
      window.setupHelpDialogListeners();

      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(fetchMock).not.toHaveBeenCalled();
    });

    it("does not overwrite the body when the fetch response is not ok", async () => {
      const { link, body } = createHelpDialog("ui_chat");
      vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false })));
      window.setupHelpDialogListeners();

      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(body.innerHTML.trim()).toBe("");
    });

    it("does not call show() again when the dialog is already open", () => {
      const { link, dialog } = createHelpDialog("ui_chat", { open: true, bodyHtml: "<p>x</p>" });
      window.setupHelpDialogListeners();

      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(dialog.show).not.toHaveBeenCalled();
    });

    it("does nothing when the trigger has no matching dialog", () => {
      container = document.createElement("div");
      const link = document.createElement("a");
      link.className = "adapter-help-trigger";
      link.setAttribute("data-channel-type", "missing_type");
      container.appendChild(link);
      document.body.appendChild(container);

      window.setupHelpDialogListeners();

      expect(() =>
        link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true })),
      ).not.toThrow();
    });

    it("closes the dialog when the close button is clicked", () => {
      const { dialog, closeBtn } = createHelpDialog("ui_chat");
      window.setupHelpDialogListeners();

      closeBtn.dispatchEvent(new MouseEvent("click", { bubbles: true }));

      expect(dialog.close).toHaveBeenCalledTimes(1);
    });
  });

  describe("positionHelpDialog", () => {
    it("positions the dialog below and left-aligned to the trigger, clamped to the viewport", () => {
      const { link, dialog } = createHelpDialog("ui_chat");
      link.getBoundingClientRect = () => ({ top: 100, left: 100, right: 150, bottom: 120, width: 50, height: 20 });
      dialog.getBoundingClientRect = () => ({ top: 0, left: 0, right: 0, bottom: 0, width: 60, height: 40 });

      window.positionHelpDialog(dialog, link);

      expect(dialog.style.top).toBe("128px");
      expect(dialog.style.left).toBe("90px");
      expect(dialog.style.margin).toBe("0px");
    });

    it("clamps the position so the dialog stays within the viewport", () => {
      const { link, dialog } = createHelpDialog("ui_chat");
      link.getBoundingClientRect = () => ({
        top: window.innerHeight - 5,
        left: window.innerWidth - 5,
        right: window.innerWidth,
        bottom: window.innerHeight,
        width: 5,
        height: 5,
      });
      dialog.getBoundingClientRect = () => ({ top: 0, left: 0, right: 0, bottom: 0, width: 300, height: 300 });

      window.positionHelpDialog(dialog, link);

      const maxLeft = Math.max(window.innerWidth - 300 - 8, 8);
      const maxTop = Math.max(window.innerHeight - 300 - 8, 8);
      expect(dialog.style.left).toBe(`${maxLeft}px`);
      expect(dialog.style.top).toBe(`${maxTop}px`);
    });
  });

  describe("setupHelpDialogDragging", () => {
    it("drags the dialog on mousedown/mousemove and stops on mouseup", () => {
      const { dialog, header } = createHelpDialog("ui_chat");
      dialog.getBoundingClientRect = () => ({ top: 50, left: 50, right: 250, bottom: 150, width: 200, height: 100 });

      window.setupHelpDialogDragging();

      header.dispatchEvent(
        new MouseEvent("mousedown", { bubbles: true, cancelable: true, clientX: 60, clientY: 60 }),
      );
      expect(dialog.style.margin).toBe("0px");

      document.dispatchEvent(new MouseEvent("mousemove", { bubbles: true, clientX: 80, clientY: 90 }));
      expect(dialog.style.left).toBe("70px");
      expect(dialog.style.top).toBe("80px");

      document.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
      // A further mousemove after mouseup must not move the dialog anymore.
      document.dispatchEvent(new MouseEvent("mousemove", { bubbles: true, clientX: 500, clientY: 500 }));
      expect(dialog.style.left).toBe("70px");
    });

    it("does not start dragging when mousedown originates on the close button", () => {
      const { header, closeBtn, dialog } = createHelpDialog("ui_chat");
      window.setupHelpDialogDragging();

      closeBtn.dispatchEvent(
        new MouseEvent("mousedown", { bubbles: true, cancelable: true, clientX: 5, clientY: 5 }),
      );
      document.dispatchEvent(new MouseEvent("mousemove", { bubbles: true, clientX: 200, clientY: 200 }));

      expect(dialog.style.left).toBe("");
      void header;
    });

    it("does nothing when the dialog has no header", () => {
      container = document.createElement("div");
      const dialog = document.createElement("dialog");
      dialog.className = "adapter-help-dialog";
      container.appendChild(dialog);
      document.body.appendChild(container);

      expect(() => window.setupHelpDialogDragging()).not.toThrow();
    });
  });

  describe("auto-init on DOMContentLoaded", () => {
    let cleanup;

    afterEach(() => {
      cleanup?.removeRegisteredListeners();
      cleanup = undefined;
    });

    it("wires up adapter visibility, datalists, binding isolation, and help dialogs together", async () => {
      const { checkbox, settingsDiv } = createAdapterVisibilityDOM("ui_chat", { checked: true });

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/ai_helper_chat_settings");

      // setAdapterSettingsVisible ran once for the already-checked adapter.
      expect(settingsDiv.style.display).toBe("");
      void checkbox;
    });
  });
});
