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

  function addContentDiv() {
    contentDiv = document.createElement("div");
    contentDiv.id = "content";
    document.body.appendChild(contentDiv);
    return contentDiv;
  }

  function addProjectHierarchyWithMultipleBookmarks(contentDiv, bookmarkedProjectCount = 2) {
    const projectBoard = document.createElement("ul");
    for (let index = 0; index < bookmarkedProjectCount; index += 1) {
      const projectItem = document.createElement("li");
      const projectItemContent = document.createElement("div");
      const projectLink = document.createElement("a");
      projectLink.href = "#";
      projectLink.textContent = `Project ${index + 1}`;
      projectItemContent.appendChild(projectLink);
      const bookmarkIcon = document.createElement("span");
      bookmarkIcon.className = "icon icon-bookmarked-project";
      projectItemContent.appendChild(bookmarkIcon);
      projectItem.appendChild(projectItemContent);
      projectBoard.appendChild(projectItem);
    }
    contentDiv.appendChild(projectBoard);
    return projectBoard;
  }

  function addProjectListWithMultipleBookmarks(contentDiv, bookmarkedProjectCount = 2) {
    const projectList = document.createElement("table");
    for (let index = 0; index < bookmarkedProjectCount; index += 1) {
      const projectRow = document.createElement("tr");
      const projectNameCell = document.createElement("td");
      const projectLink = document.createElement("a");
      projectLink.href = "#";
      projectLink.appendChild(document.createTextNode(`Project ${index + 1}`));
      projectNameCell.appendChild(projectLink);
      const bookmarkIcon = document.createElement("span");
      bookmarkIcon.className = "icon icon-bookmarked-project";
      projectNameCell.appendChild(bookmarkIcon);
      projectRow.appendChild(projectNameCell);
      projectList.appendChild(projectRow);
    }
    contentDiv.appendChild(projectList);
    return projectList;
  }

  function addLegendParagraph(contentDiv) {
    legendParagraph = document.createElement("p");
    bookmarkIcon = document.createElement("span");
    bookmarkIcon.className = "icon icon-bookmarked-project";
    legendParagraph.appendChild(bookmarkIcon);
    contentDiv.appendChild(legendParagraph);
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
    const content = addContentDiv();
    addLegendParagraph(content);

    const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_legend/ai_helper_project_legend");

    expect(legendItem.hidden).toBe(false);
    expect(legendItem.parentElement).toBe(legendParagraph);
    expect(legendParagraph.lastElementChild).toBe(legendItem);
    cleanup.removeRegisteredListeners();
  });

  it("appends the legend item to the last bookmarked-project icon when multiple icons exist on the project board", async () => {
    addLegendItem();
    const content = addContentDiv();
    addProjectHierarchyWithMultipleBookmarks(content, 2);
    addLegendParagraph(content);

    const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_legend/ai_helper_project_legend");

    expect(legendItem.hidden).toBe(false);
    expect(legendItem.parentElement).toBe(legendParagraph);
    expect(legendParagraph.lastElementChild).toBe(legendItem);
    cleanup.removeRegisteredListeners();
  });

  it("appends the legend item to the last bookmarked-project icon when multiple icons exist on the project list", async () => {
    addLegendItem();
    const content = addContentDiv();
    addProjectListWithMultipleBookmarks(content, 2);
    addLegendParagraph(content);

    const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_legend/ai_helper_project_legend");

    expect(legendItem.hidden).toBe(false);
    expect(legendItem.parentElement).toBe(legendParagraph);
    expect(legendParagraph.lastElementChild).toBe(legendItem);
    cleanup.removeRegisteredListeners();
  });

  it("does nothing when the legend item is absent", async () => {
    const content = addContentDiv();
    addLegendParagraph(content);

    const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_legend/ai_helper_project_legend");

    expect(bookmarkIcon.parentElement).toBe(legendParagraph);
    expect(legendParagraph.children).toHaveLength(1);
    cleanup.removeRegisteredListeners();
  });

  it("does nothing and leaves the legend item hidden when the legend paragraph is absent", async () => {
    addLegendItem();
    addContentDiv();

    const cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_legend/ai_helper_project_legend");

    expect(legendItem.hidden).toBe(true);
    expect(legendItem.parentElement).toBe(document.body);
    cleanup.removeRegisteredListeners();
  });
});
