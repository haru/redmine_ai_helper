import { afterEach, describe, expect, it } from "vitest";
import { loadScript } from "../support/load_script.js";

// T043: characterization tests for custom_commands/_form.html.erb extraction.

describe("AiHelperCustomCommands", () => {
  let commandTypeField;
  let userScopeField;
  let userScopeSelect;

  function addForm({ withUserScopeSelect = true, initialType = "common" } = {}) {
    commandTypeField = document.createElement("select");
    commandTypeField.id = "ai_helper_custom_command_command_type";
    ["common", "user"].forEach((value) => {
      const option = document.createElement("option");
      option.value = value;
      commandTypeField.appendChild(option);
    });
    commandTypeField.value = initialType;
    document.body.appendChild(commandTypeField);

    userScopeField = document.createElement("p");
    userScopeField.id = "user_scope_field";
    document.body.appendChild(userScopeField);

    if (withUserScopeSelect) {
      userScopeSelect = document.createElement("select");
      userScopeSelect.id = "ai_helper_custom_command_user_scope";
      document.body.appendChild(userScopeSelect);
    }
  }

  afterEach(() => {
    commandTypeField?.remove();
    userScopeField?.remove();
    userScopeSelect?.remove();
    commandTypeField = undefined;
    userScopeField = undefined;
    userScopeSelect = undefined;
    delete window.AiHelperCustomCommands;
  });

  async function load() {
    await loadScript("assets/javascripts/settings/ai_helper_custom_commands");
  }

  it("hides the user-scope field on init when command type is not 'user'", async () => {
    addForm({ initialType: "common" });
    await load();

    window.AiHelperCustomCommands.init();

    expect(userScopeField.style.display).toBe("none");
  });

  it("shows the user-scope field on init when command type is 'user'", async () => {
    addForm({ initialType: "user" });
    await load();

    window.AiHelperCustomCommands.init();

    expect(userScopeField.style.display).toBe("");
  });

  it("shows the user-scope field when the command type changes to 'user'", async () => {
    addForm({ initialType: "common" });
    await load();
    window.AiHelperCustomCommands.init();

    commandTypeField.value = "user";
    commandTypeField.dispatchEvent(new Event("change", { bubbles: true }));

    expect(userScopeField.style.display).toBe("");
  });

  it("hides the user-scope field when the command type changes away from 'user'", async () => {
    addForm({ initialType: "user" });
    await load();
    window.AiHelperCustomCommands.init();

    commandTypeField.value = "common";
    commandTypeField.dispatchEvent(new Event("change", { bubbles: true }));

    expect(userScopeField.style.display).toBe("none");
  });

  it("also reacts to changes on the user-scope select itself", async () => {
    addForm({ initialType: "user" });
    await load();
    window.AiHelperCustomCommands.init();

    commandTypeField.value = "common";
    userScopeSelect.dispatchEvent(new Event("change", { bubbles: true }));

    expect(userScopeField.style.display).toBe("none");
  });

  it("does nothing when the user-scope select does not exist on the page", async () => {
    addForm({ withUserScopeSelect: false, initialType: "common" });
    await load();

    expect(() => window.AiHelperCustomCommands.init()).not.toThrow();
    expect(userScopeField.style.display).toBe("none");
  });

  it("does nothing when the command type field is absent", async () => {
    await load();
    expect(() => window.AiHelperCustomCommands.init()).not.toThrow();
  });
});
