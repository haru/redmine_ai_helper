"use strict";

function setAdapterSettingsVisible(channelType) {
  const checkbox = document.querySelector(
    `input[type=checkbox][data-adapter-type="${channelType}"]`
  );
  const settingsDiv = document.getElementById(`adapter-settings-${channelType}`);
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
        function (option) { return option.textContent === enteredText; }
      );
      hiddenInput.value = matched ? matched.getAttribute("value") : "";
    }

    textInput.addEventListener("input", syncHiddenInput);
    textInput.addEventListener("blur", syncHiddenInput);
  });
}

document.addEventListener("DOMContentLoaded", function () {
  const adapterTypes = setupAdapterCheckboxListeners();
  adapterTypes.forEach(function (channelType) {
    setAdapterSettingsVisible(channelType);
  });
  setupDatalistHandlers();
});
