import { afterEach, beforeEach, describe, expect, it } from "vitest";
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
    if (container) container.remove();
    container = undefined;
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
});
