/**
 * Custom command form: toggle the user-scope field's visibility based on
 * the selected command type.
 * Extracted from custom_commands/_form.html.erb.
 */
const AiHelperCustomCommands = (() => {
  function init() {
    const commandTypeField = document.getElementById('ai_helper_custom_command_command_type');
    const userScopeField = document.getElementById('user_scope_field');
    const userScopeSelect = document.getElementById('ai_helper_custom_command_user_scope');

    if (!commandTypeField || !userScopeField) {return;}

    function updateVisibility() {
      const commandType = commandTypeField.value;
      if (commandType === 'user') {
        userScopeField.style.display = '';
      } else {
        userScopeField.style.display = 'none';
      }
    }

    commandTypeField.addEventListener('change', updateVisibility);
    if (userScopeSelect) {
      userScopeSelect.addEventListener('change', updateVisibility);
    }
    updateVisibility();
  }

  return { init };
})();

window.AiHelperCustomCommands = AiHelperCustomCommands;
