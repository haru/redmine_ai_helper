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
  setupHelpDialogListeners();
  setupHelpDialogDragging();
});

function setupHelpDialogListeners() {
  document.querySelectorAll(".adapter-help-trigger").forEach(function (link) {
    link.addEventListener("click", function (e) {
      e.preventDefault();
      const channelType = this.getAttribute("data-channel-type");
      const dialog = document.getElementById(
        "adapter-help-dialog-" + channelType
      );
      if (!dialog) return;

      const body = dialog.querySelector(".adapter-help-dialog-body");
      if (body && !body.innerHTML.trim()) {
        const url = this.getAttribute("href");
        fetch(url)
          .then(function (response) {
            if (!response.ok) return null;
            return response.text();
          })
          .then(function (html) {
            if (html) body.innerHTML = html;
          });
      }

      if (!dialog.open) dialog.show();
      positionHelpDialog(dialog, this);
    });
  });

  document.querySelectorAll(".adapter-help-dialog-close").forEach(function (btn) {
    btn.addEventListener("click", function () {
      const dialog = this.closest("dialog");
      if (dialog) dialog.close();
    });
  });
}

function positionHelpDialog(dialog, trigger) {
  const margin = 8;
  const linkRect = trigger.getBoundingClientRect();
  const dialogRect = dialog.getBoundingClientRect();

  let top = linkRect.bottom + margin;
  let left = linkRect.right - dialogRect.width;

  const maxLeft = Math.max(window.innerWidth - dialogRect.width - margin, margin);
  const maxTop = Math.max(window.innerHeight - dialogRect.height - margin, margin);
  left = Math.min(Math.max(left, margin), maxLeft);
  top = Math.min(Math.max(top, margin), maxTop);

  dialog.style.margin = "0";
  dialog.style.top = top + "px";
  dialog.style.left = left + "px";
}

function setupHelpDialogDragging() {
  document.querySelectorAll(".adapter-help-dialog").forEach(function (dialog) {
    const header = dialog.querySelector(".adapter-help-dialog-header");
    if (!header) return;

    let dragging = false;
    let startX = 0;
    let startY = 0;
    let startLeft = 0;
    let startTop = 0;

    function onMouseMove(e) {
      if (!dragging) return;
      const dialogRect = dialog.getBoundingClientRect();
      const maxLeft = Math.max(window.innerWidth - dialogRect.width, 0);
      const maxTop = Math.max(window.innerHeight - dialogRect.height, 0);
      let left = Math.min(Math.max(startLeft + (e.clientX - startX), 0), maxLeft);
      let top = Math.min(Math.max(startTop + (e.clientY - startY), 0), maxTop);
      dialog.style.left = left + "px";
      dialog.style.top = top + "px";
    }

    function onMouseUp() {
      dragging = false;
      document.removeEventListener("mousemove", onMouseMove);
      document.removeEventListener("mouseup", onMouseUp);
    }

    header.addEventListener("mousedown", function (e) {
      if (e.target.closest(".adapter-help-dialog-close")) return;
      dragging = true;
      const rect = dialog.getBoundingClientRect();
      startX = e.clientX;
      startY = e.clientY;
      startLeft = rect.left;
      startTop = rect.top;
      dialog.style.margin = "0";
      document.addEventListener("mousemove", onMouseMove);
      document.addEventListener("mouseup", onMouseUp);
      e.preventDefault();
    });
  });
}
