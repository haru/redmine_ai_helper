import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// Classes of the editor elements that must stay at z-index: auto (ADR-041).
// Matched as class-name prefixes, so variants such as
// .ai-helper-typo-overlay-active are covered too.
const EDITOR_CLASSES = [
  "ai-helper-textarea-overlay",
  "ai-helper-textarea-positioned",
  "ai-helper-scrollable-overlay",
  "ai-helper-typo-overlay",
  "ai-helper-typo-control-panel",
  "ai-helper-control-panel-positioned",
];

/**
 * Reads the plugin stylesheet from disk, with comments stripped.
 * @returns {string} the CSS source without comments
 */
function readCss() {
  // Vitest runs with the plugin root as the working directory
  const css = readFileSync(resolve(process.cwd(), "assets/stylesheets/ai_helper.css"), "utf8");
  return css.replace(/\/\*[\s\S]*?\*\//g, "");
}

/**
 * Splits the stylesheet into its innermost rules, including rules nested in
 * @media blocks. This is a lightweight scan, not a CSS parser: jsdom cannot
 * compute cascade or paint order, so the stacking contract is checked at the
 * source level instead (see ADR-041).
 * @returns {{selectors: string[], body: string}[]} each rule's selector list
 *   and declaration block
 */
function getRules() {
  const css = readCss();
  const rules = [];
  const re = /([^{}]+)\{([^{}]*)\}/g;
  let match;
  while ((match = re.exec(css)) !== null) {
    const selectors = match[1].split(",").map((s) => s.trim()).filter(Boolean);
    rules.push({ selectors, body: match[2] });
  }
  return rules;
}

/**
 * Returns the subject (rightmost compound) of a selector, the element the
 * rule actually styles.
 * @param {string} selector e.g. ".ai-helper-typo-overlay .ai-helper-tooltip"
 * @returns {string} e.g. ".ai-helper-tooltip"
 */
function subjectOf(selector) {
  const compounds = selector.split(/[\s>+~]+/).filter(Boolean);
  return compounds[compounds.length - 1];
}

/**
 * Tells whether a selector styles one of the editor elements.
 * @param {string} selector a single selector (no commas)
 * @returns {boolean} true when its subject carries an editor class
 */
function targetsEditorElement(selector) {
  const subject = subjectOf(selector);
  return EDITOR_CLASSES.some((cls) => subject.includes(`.${cls}`));
}

describe("editor stacking CSS contract", () => {
  it(".ai-helper-tooltip keeps z-index 10001 (exempt from the contract)", () => {
    const tooltipRule = getRules().find((rule) => rule.selectors.includes(".ai-helper-tooltip"));

    expect(tooltipRule, ".ai-helper-tooltip rule not found in ai_helper.css").toBeDefined();
    expect(tooltipRule.body).toMatch(/z-index:\s*10001/);
  });

  it.each(EDITOR_CLASSES)("finds at least one rule for .%s", (cls) => {
    // Guards against the contract below passing vacuously after a rename
    const found = getRules().some((rule) => rule.selectors.some((s) => s.includes(`.${cls}`)));
    expect(found).toBe(true);
  });

  it("no rule styling an editor element sets a z-index", () => {
    const offenders = getRules()
      .filter((rule) => rule.selectors.some(targetsEditorElement))
      .filter((rule) => /z-index/.test(rule.body))
      .map((rule) => rule.selectors.join(", "));

    expect(offenders).toEqual([]);
  });
});
