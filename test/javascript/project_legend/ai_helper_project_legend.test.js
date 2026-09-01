import { afterEach, describe, expect, it } from "vitest";
import { loadScriptAndFireDOMContentLoaded } from "../support/dom_content_loaded.js";

describe("ai_helper_project_legend", () => {
  let legendItem;
  let legendParagraph;
  let bookmarkIcon;
  let contentDiv;

  function addLegendItem() {
    legendItem = document.createElement("span");
    legendItem.id = "ai-helper-index-legend-item";
    legendItem.hidden = true;
    document.body.appendChild(legendItem);
    return legendItem;
  }

  function addLegendParagraph() {
    contentDiv = document.createElement("div");
    contentDiv.id = "content";

    legendParagraph = document.createElement("p");
    bookmarkIcon = document.createElement("span");
    bookmarkIcon.className = "icon icon-bookmarked-project";
    legendParagraph.appendChild(bookmarkIcon);
    contentDiv.appendChild(legendParagraph);
    document.body.appendChild(contentDiv);
    return legendParagraph;
  }

  afterEach(() => {
    legendItem?.remove();
    legendParagraph?.remove();
    contentDiv?.remove();
    legendItem = undefined;
    legendParagraph = undefined;
    bookmarkIcon = undefined;
    contentDiv = undefined;
  });

  it("unhides the legend item and appends it to the legend paragraph when both exist", async () => {
    addLegendItem();
    addLegendParagraph();

    const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_legend/ai_helper_project_legend");

    expect(legendItem.hidden).toBe(false);
    expect(legendItem.parentElement).toBe(legendParagraph);
    expect(legendParagraph.lastElementChild).toBe(legendItem);
    cleanup.removeRegisteredListeners();
  });

  it("does nothing when the legend item is absent", async () => {
    addLegendParagraph();

    const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_legend/ai_helper_project_legend");

    expect(bookmarkIcon.parentElement).toBe(legendParagraph);
    expect(legendParagraph.children).toHaveLength(1);
    cleanup.removeRegisteredListeners();
  });

  it("does nothing and leaves the legend item hidden when the legend paragraph is absent", async () => {
    addLegendItem();

    const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_legend/ai_helper_project_legend");

    expect(legendItem.hidden).toBe(true);
    expect(legendItem.parentElement).toBe(document.body);
    cleanup.removeRegisteredListeners();
  });
});
