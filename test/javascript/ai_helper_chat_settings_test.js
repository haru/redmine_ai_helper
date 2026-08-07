// Tests for the channels tab settings JS (assets/javascripts/ai_helper_chat_settings.js).
// These cover two fixes:
//   1. syncHiddenInput must match datalist options by their `value` (the user
//      name, what the browser actually writes into the text input when a
//      suggestion is picked) and copy the id from `data-user-id`, not the
//      option's textContent/value pair used before the fix.
//   2. setupBindingFormIsolation must disable every other adapter's
//      "add binding" fields before a submit so same-named fields from other
//      adapters are not sent along with the clicked adapter's binding.
//
// To run these tests, a JavaScript test environment (e.g., Jest + jsdom) is
// required. If no JS test environment is available, verify manually using
// the running app: PR #354 review comments on
// app/views/ai_helper_settings/_channels_tab.html.erb and
// assets/javascripts/ai_helper_chat_settings.js describe the original bugs.

/**
 * Helper: build a minimal datalist + text input + hidden input trio,
 * matching the markup rendered by _channels_tab.html.erb.
 */
function createDatalistDOM(channelType, users) {
  const container = document.createElement("div");

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
  return { container, textInput, hiddenInput };
}

// Test 1: selecting a datalist option (browser writes its `value`, the user
// name, into the input) resolves the correct user id into the hidden field.
function testSyncHiddenInputMatchesByNameValue() {
  const { container, textInput, hiddenInput } = createDatalistDOM("ui_chat", [
    { id: 3, name: "Dave Lopper" },
    { id: 7, name: "Redmine Admin" }
  ]);

  textInput.value = "Dave Lopper";
  textInput.dispatchEvent(new Event("input", { bubbles: true }));

  console.assert(hiddenInput.value === "3",
    `Test 1 FAILED: expected hidden user id '3', got '${hiddenInput.value}'`);

  container.remove();
  console.log("Test 1 PASSED: selecting an option by its name value resolves the correct user id");
}

// Test 2: text that does not match any option clears the hidden id.
function testSyncHiddenInputClearsOnNoMatch() {
  const { container, textInput, hiddenInput } = createDatalistDOM("ui_chat", [
    { id: 3, name: "Dave Lopper" }
  ]);

  textInput.value = "Someone Else";
  textInput.dispatchEvent(new Event("input", { bubbles: true }));

  console.assert(hiddenInput.value === "",
    `Test 2 FAILED: expected hidden user id to be cleared, got '${hiddenInput.value}'`);

  container.remove();
  console.log("Test 2 PASSED: non-matching text clears the hidden user id");
}

/**
 * Helper: build two adapter binding fieldsets sharing the same field names,
 * matching the markup rendered once per adapter by _channels_tab.html.erb.
 */
function createBindingFieldsets(channelTypes) {
  const container = document.createElement("div");
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
  return { container, fieldsets };
}

// Test 3: clicking one adapter's "add binding" submit disables every other
// adapter's same-named fields, so only the clicked adapter's fields would be
// serialized on submit.
function testBindingFormIsolationDisablesOtherAdapters() {
  const { container, fieldsets } = createBindingFieldsets(["ui_chat", "fake_other"]);

  setupBindingFormIsolation();
  fieldsets.ui_chat.submitButton.click();

  console.assert(fieldsets.ui_chat.channelIdInput.disabled === false,
    "Test 3 FAILED: the clicked adapter's own fields must stay enabled");
  console.assert(fieldsets.fake_other.channelIdInput.disabled === true,
    "Test 3 FAILED: the other adapter's fields must be disabled");
  console.assert(fieldsets.fake_other.channelTypeInput.disabled === true,
    "Test 3 FAILED: the other adapter's hidden channel_type field must be disabled");

  container.remove();
  console.log("Test 3 PASSED: clicking an adapter's add-binding button isolates its fields");
}

// Test 4: clicking the other adapter's submit afterwards flips which
// fieldset is enabled/disabled.
function testBindingFormIsolationSwitchesActiveAdapter() {
  const { container, fieldsets } = createBindingFieldsets(["ui_chat", "fake_other"]);

  setupBindingFormIsolation();
  fieldsets.ui_chat.submitButton.click();
  fieldsets.fake_other.submitButton.click();

  console.assert(fieldsets.fake_other.channelIdInput.disabled === false,
    "Test 4 FAILED: the newly clicked adapter's fields must be re-enabled");
  console.assert(fieldsets.ui_chat.channelIdInput.disabled === true,
    "Test 4 FAILED: the previously active adapter's fields must now be disabled");

  container.remove();
  console.log("Test 4 PASSED: switching the clicked adapter re-isolates fields correctly");
}

// Run all tests
function runAllTests() {
  console.log("=== Chat Settings JS Fix Tests ===\n");

  testSyncHiddenInputMatchesByNameValue();
  testSyncHiddenInputClearsOnNoMatch();
  testBindingFormIsolationDisablesOtherAdapters();
  testBindingFormIsolationSwitchesActiveAdapter();

  console.log("\n=== All tests completed ===");
}

// Export for module environments, or run directly
if (typeof module !== "undefined" && module.exports) {
  module.exports = { runAllTests };
} else if (typeof window !== "undefined") {
  window.runChatSettingsTests = runAllTests;
}
