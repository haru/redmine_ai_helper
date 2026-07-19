"use strict";

function setAdapterSettingsVisible(channelType) {
  const checkbox = document.querySelector(
    `input[type=checkbox][data-adapter-type="${channelType}"]`
  );
  const settingsDiv = document.getElementById(`adapter-settings-${channelType}`);
  const bindingsFieldset = document.getElementById(`adapter-bindings-${channelType}`);
  if (!checkbox || !settingsDiv || !bindingsFieldset) return;
  const display = checkbox.checked ? "" : "none";
  settingsDiv.style.display = display;
  bindingsFieldset.style.display = display;
}

function setupAdapterCheckboxListeners() {
  const checkboxes = document.querySelectorAll(".adapter-enabled-checkbox");
  const adapterTypes = [];
  checkboxes.forEach(function (checkbox) {
    const channelType = checkbox.getAttribute("data-adapter-type");
    if (channelType) {
      adapterTypes.push(channelType);
      checkbox.addEventListener("change", function () {
        setAdapterSettingsVisible(channelType);
      });
    }
  });
  return adapterTypes;
}

function setupDatalistHandlers() {
  const textInputs = document.querySelectorAll(
    'input[list^="ai-helper-users-datalist-"]'
  );
  textInputs.forEach(function (textInput) {
    const listAttr = textInput.getAttribute("list");
    const channelType = listAttr.replace("ai-helper-users-datalist-", "");
    const hiddenInput = document.querySelector(
      `input[type=hidden][name="chat_adapter_settings\\[${channelType}\\]\\[redmine_user_id\\]"]`
    );
    if (!hiddenInput) return;

    function syncHiddenInput() {
      const enteredText = textInput.value.trim();
      const datalist = document.getElementById(listAttr);
      if (!datalist) return;

      const matched = Array.from(datalist.querySelectorAll("option")).find(
        function (option) { return option.getAttribute("value") === enteredText; }
      );
      hiddenInput.value = matched ? matched.getAttribute("data-user-id") : "";
    }

    textInput.addEventListener("input", syncHiddenInput);
    textInput.addEventListener("blur", syncHiddenInput);
  });
}

// Each adapter's "add binding" fields share the same `name` attributes
// (they all live inside the single settings <form>), so submitting one
// adapter's fields would otherwise carry along every other adapter's
// same-named fields. Disable every other adapter's fields right before
// submission so only the clicked adapter's binding is submitted.
function setupBindingFormIsolation() {
  const bindingFieldsets = document.querySelectorAll(
    'fieldset[id^="adapter-bindings-"]'
  );

  function bindingFields(fieldset) {
    return fieldset.querySelectorAll(
      'input[name^="ai_helper_channel_binding"], select[name^="ai_helper_channel_binding"]'
    );
  }

  bindingFieldsets.forEach(function (fieldset) {
    const submitButtons = fieldset.querySelectorAll(
      "input[type=submit][formaction], button[type=submit][formaction]"
    );
    submitButtons.forEach(function (button) {
      button.addEventListener("click", function () {
        bindingFieldsets.forEach(function (otherFieldset) {
          const disable = otherFieldset !== fieldset;
          bindingFields(otherFieldset).forEach(function (field) {
            field.disabled = disable;
          });
        });
      });
    });
  });
}

document.addEventListener("DOMContentLoaded", function () {
  const adapterTypes = setupAdapterCheckboxListeners();
  adapterTypes.forEach(function (channelType) {
    setAdapterSettingsVisible(channelType);
  });
  setupDatalistHandlers();
  setupBindingFormIsolation();
});
