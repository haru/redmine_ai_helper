/**
 * Placement of the AI Helper control containers (completion checkbox,
 * duplicate-check link) that belong to a Redmine wiki-toolbar textarea.
 *
 * Redmine's jsToolBar wraps the textarea as
 * `div.jstBlock > (div.jstTabs + div.jstEditor > (textarea + preview))`.
 * Inserting a container right after the textarea would put it inside
 * `.jstEditor`, before the preview element, so it would jump above the
 * preview text when the preview tab is selected. The container is therefore
 * placed after the whole `.jstBlock` (issue #541).
 */
const AiHelperEditorControls = (() => {
  /**
   * Move `container` right after the textarea's `.jstBlock` (or right after
   * the textarea itself when there is no toolbar) and reveal it.
   * @param {HTMLTextAreaElement} textarea - The textarea the container belongs to.
   * @param {HTMLElement} container - The element to move.
   */
  function placeAfterEditor(textarea, container) {
    // Without the wiki toolbar (text format "none") there are no tabs and no
    // preview, so the textarea itself is the anchor.
    const anchor = textarea.closest('.jstBlock') || textarea;
    anchor.parentNode.insertBefore(container, anchor.nextSibling);
    container.style.display = 'block';
  }

  return { placeAfterEditor };
})();
window.AiHelperEditorControls = AiHelperEditorControls;
