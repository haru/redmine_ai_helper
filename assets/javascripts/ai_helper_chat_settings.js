"use strict";

function setAdapterSettingsVisible(channelType) {
  const checkbox = document.querySelector(
    'input[type=checkbox][data-adapter-type="' + channelType + '"]'
  );
  const settingsDiv = document.getElementById("adapter-settings-" + channelType);
  if (!checkbox || !settingsDiv) return;
  settingsDiv.style.display = checkbox.checked ? "" : "none";
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
  const hiddenInputs = document.querySelectorAll(
    'input[type=hidden][name*="[redmine_user_id]"]'
  );
  hiddenInputs.forEach(function (hiddenInput) {
    const name = hiddenInput.getAttribute("name");
    const match = name.match(
      /^chat_adapter_settings\[([^\]]+)\]\[redmine_user_id\]$/
    );
    if (!match) return;

    const channelType = match[1];
    const textInput = document.querySelector(
      'input[list="ai-helper-users-datalist-' + channelType + '"]'
    );
    if (!textInput) return;

    textInput.addEventListener("input", function () {
      const enteredText = textInput.value.trim();
      const datalistId = textInput.getAttribute("list");
      const datalist = document.getElementById(datalistId);
      if (!datalist) return;

      let matched = false;
      const options = datalist.querySelectorAll("option");
      for (let i = 0; i < options.length; i++) {
        if (options[i].textContent === enteredText) {
          hiddenInput.value = options[i].getAttribute("value");
          matched = true;
          break;
        }
      }
      if (!matched) {
        hiddenInput.value = "";
      }
    });
  });
}

document.addEventListener("DOMContentLoaded", function () {
  const adapterTypes = setupAdapterCheckboxListeners();
  adapterTypes.forEach(function (channelType) {
    setAdapterSettingsVisible(channelType);
  });
  setupDatalistHandlers();
});
