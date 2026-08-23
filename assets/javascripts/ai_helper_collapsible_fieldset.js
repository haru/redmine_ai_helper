/**
 * Shared open/closed-state toggling for the plugin's several collapsible
 * fieldsets (issue reply, wiki summary, issue summary). Each caller keeps
 * its own localStorage key and value format (they predate this shared
 * helper and differ from each other), so only the DOM toggle mechanics are
 * unified here.
 */
const AiHelperCollapsibleFieldset = (() => {
  /**
   * Toggle the open/closed state of a fieldset to match `flag`.
   * @param {string} fieldsetId
   * @param {boolean} flag - true to expand, false to collapse.
   */
  function setExpanded(fieldsetId, flag) {
    const fieldset = document.getElementById(fieldsetId);
    if (!fieldset) return;
    const legend = fieldset.querySelector('legend');
    const isOpen = !fieldset.classList.contains('collapsed');
    if (isOpen !== flag) {
      toggleFieldset(legend);
    }
  }

  return { setExpanded };
})();
window.AiHelperCollapsibleFieldset = AiHelperCollapsibleFieldset;

/**
 * Collapsible fieldset open/closed-state persistence for the issue reply
 * panel, plus the (otherwise unrelated) reply-generation trigger that shares
 * this same source file.
 * Extracted from issues/_form.html.erb.
 */

/**
 * Toggle the open/closed state of the reply fieldset.
 * @param {boolean} flag - true to expand, false to collapse.
 */
function aiHelperSetReplyExpanded(flag) {
  AiHelperCollapsibleFieldset.setExpanded('ai-helper-reply-fields', flag);
}

/**
 * Save the open/closed state of the reply fieldset to localStorage.
 * Exposed on `window` because the fieldset legend's inline `onclick` calls
 * it directly.
 */
function aiHelperSaveReplyState() {
  const container = document.getElementById('ai-helper-reply-fields');
  const isOpen = !container.classList.contains('collapsed');
  const config = JSON.parse(container.dataset.config || '{}');
  const state = { replyExpanded: isOpen };
  localStorage.setItem('aiHelperReplyState_' + config.userId, JSON.stringify(state));
}
window.aiHelperSaveReplyState = aiHelperSaveReplyState;

/**
 * Trigger AI-generated reply text for the given issue.
 * Exposed on `window` because the "generate" button's inline `onclick`
 * calls it directly.
 * @param {number} _issueId - unused; the issue ID and config are read from the
 *   '#ai-helper-reply-fields' container's data-config instead.
 */
function ai_helper_generate_reply(_issueId) {
  const container = document.getElementById('ai-helper-reply-fields');
  const config = JSON.parse(container.dataset.config || '{}');
  const instructions = document.getElementById('ai-helper-reply-instructions').value;
  ai_helper.generateReplyStream(
    config.generateReplyUrl,
    instructions,
    config.errorMessage,
    config.applyLabel,
    config.copyIconHtml
  );
}
window.ai_helper_generate_reply = ai_helper_generate_reply;

document.addEventListener('DOMContentLoaded', function() {
  const container = document.getElementById('ai-helper-reply-fields');
  if (!container) return;
  const config = JSON.parse(container.dataset.config || '{}');

  const state = localStorage.getItem('aiHelperReplyState_' + config.userId);
  if (state) {
    const parsedState = JSON.parse(state);
    if (parsedState.replyExpanded) {
      aiHelperSetReplyExpanded(true);
    } else {
      aiHelperSetReplyExpanded(false);
    }
  }
});
