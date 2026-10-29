/**
 * Builds the DOM that Redmine's jsToolBar renders around a textarea,
 * matching app/assets/javascripts/jstoolbar/jstoolbar.js (lines 25-36 and
 * 64-65): `div.jstBlock > (div.jstTabs.tabs + div.jstEditor > (textarea +
 * div#preview_<id>.wiki.wiki-preview.hidden))`. The block is returned
 * detached; callers put it where the real ERB puts the textarea.
 *
 * @param {string} textareaId - id of the textarea; the preview id is
 *   `preview_<textareaId>`.
 * @returns {{block: HTMLElement, editor: HTMLElement, textarea: HTMLTextAreaElement, preview: HTMLElement}}
 *   The `.jstBlock` root, its `.jstEditor`, the textarea and the preview
 *   element.
 */
export function createJstEditor(textareaId) {
  const block = document.createElement("div");
  block.className = "jstBlock";

  const tabs = document.createElement("div");
  tabs.className = "jstTabs tabs";

  const editor = document.createElement("div");
  editor.className = "jstEditor";

  const textarea = document.createElement("textarea");
  textarea.id = textareaId;

  const preview = document.createElement("div");
  preview.id = `preview_${textareaId}`;
  preview.className = "wiki wiki-preview hidden";

  editor.appendChild(textarea);
  editor.appendChild(preview);
  block.appendChild(tabs);
  block.appendChild(editor);

  return { block, editor, textarea, preview };
}
