import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { loadScript } from "../support/load_script.js";
import { createJstEditor } from "../support/jst_editor.js";

/**
 * Puts a jsToolBar editor into a fresh parent that also holds a trailing
 * paragraph, so the block is not the last child.
 * @param {string} textareaId id of the textarea; the preview id is derived from it
 * @returns {{parent: HTMLElement, block: HTMLElement, editor: HTMLElement, textarea: HTMLTextAreaElement, preview: HTMLElement}} the created elements
 */
function buildJstEditor(textareaId) {
  const parent = document.createElement("div");
  const jst = createJstEditor(textareaId);
  parent.appendChild(jst.block);
  parent.appendChild(document.createElement("p"));
  document.body.appendChild(parent);
  return { parent, ...jst };
}

describe("AiHelperEditorControls.placeAfterEditor", () => {
  let parents = [];

  beforeEach(async () => {
    await loadScript("assets/javascripts/shared/ai_helper_editor_controls");
  });

  afterEach(() => {
    parents.forEach((el) => el.remove());
    parents = [];
    delete window.AiHelperEditorControls;
  });

  it("places the container right after .jstBlock, outside .jstEditor and after the preview", async () => {
    const dom = buildJstEditor("issue_description");
    parents.push(dom.parent);
    const container = document.createElement("div");
    container.id = "ai-helper-description-checkbox-container";
    container.style.display = "none";
    document.body.appendChild(container);
    parents.push(container);

    window.AiHelperEditorControls.placeAfterEditor(dom.textarea, container);

    expect(dom.block.nextElementSibling).toBe(container);
    expect(dom.editor.contains(container)).toBe(false);
    // Document order: the preview comes before the container, so the container
    // stays below the editor whichever tab is shown.
    expect(dom.preview.compareDocumentPosition(container) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it("places the container right after the textarea when there is no .jstBlock (text format none)", async () => {
    const parent = document.createElement("div");
    const textarea = document.createElement("textarea");
    textarea.id = "issue_description";
    const trailing = document.createElement("p");
    parent.appendChild(textarea);
    parent.appendChild(trailing);
    document.body.appendChild(parent);
    parents.push(parent);
    const container = document.createElement("div");
    document.body.appendChild(container);
    parents.push(container);

    window.AiHelperEditorControls.placeAfterEditor(textarea, container);

    expect(textarea.nextElementSibling).toBe(container);
    expect(container.nextElementSibling).toBe(trailing);
  });

  it("appends the container last when the anchor is the last child of its parent", async () => {
    const dom = buildJstEditor("content_text");
    parents.push(dom.parent);
    // Drop the trailing paragraph so the block has no next sibling
    dom.parent.lastElementChild.remove();
    expect(dom.block.nextSibling).toBeNull();
    const container = document.createElement("div");
    document.body.appendChild(container);
    parents.push(container);

    window.AiHelperEditorControls.placeAfterEditor(dom.textarea, container);

    expect(dom.parent.lastElementChild).toBe(container);
    expect(dom.block.nextElementSibling).toBe(container);
  });

  it("reveals the container by setting display to block", async () => {
    const dom = buildJstEditor("issue_notes");
    parents.push(dom.parent);
    const container = document.createElement("div");
    container.style.display = "none";
    document.body.appendChild(container);
    parents.push(container);

    window.AiHelperEditorControls.placeAfterEditor(dom.textarea, container);

    expect(container.style.display).toBe("block");
  });

  it("throws a TypeError instead of swallowing it when the textarea is detached", async () => {
    const textarea = document.createElement("textarea");
    const container = document.createElement("div");

    expect(() => window.AiHelperEditorControls.placeAfterEditor(textarea, container)).toThrow(TypeError);
  });
});
