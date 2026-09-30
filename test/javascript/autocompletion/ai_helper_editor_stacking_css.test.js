import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Reads the plugin stylesheet from disk.
 * @returns {string} the full CSS source
 */
function readCss() {
  // Vitest runs with the plugin root as the working directory
  return readFileSync(resolve(process.cwd(), "assets/stylesheets/ai_helper.css"), "utf8");
}

/**
 * Escapes a string for literal use inside a RegExp.
 * @param {string} text the text to escape
 * @returns {string} the escaped text
 */
function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Returns the declaration block of the first rule whose selector matches.
 * jsdom cannot compute cascade or paint order, so the stacking contract is
 * verified at the source level instead (see ADR-041).
 * @param {string} selector e.g. ".ai-helper-textarea-overlay"
 * @returns {string} the rule body between "{" and the next "}"
 */
function getRuleBody(selector) {
  const css = readCss();
  const match = new RegExp(escapeRegExp(selector) + "\\s*\\{").exec(css);
  expect(match, `selector ${selector} not found in ai_helper.css`).not.toBeNull();
  const start = match.index + match[0].length;
  const end = css.indexOf("}", start);
  return css.slice(start, end);
}

describe("editor stacking CSS contract", () => {
  describe("tooltips keep their z-index (exempt from the contract)", () => {
    it(".ai-helper-tooltip keeps z-index 10001", () => {
      expect(getRuleBody(".ai-helper-tooltip")).toMatch(/z-index:\s*10001/);
    });

    it(".ai-helper-typo-tooltip keeps z-index 10001", () => {
      expect(getRuleBody(".ai-helper-typo-tooltip")).toMatch(/z-index:\s*10001/);
    });
  });

  describe("completion overlay rules carry no z-index", () => {
    it(".ai-helper-textarea-overlay has no z-index", () => {
      expect(getRuleBody(".ai-helper-textarea-overlay")).not.toMatch(/z-index/);
    });

    it(".ai-helper-textarea-positioned has no z-index", () => {
      expect(getRuleBody(".ai-helper-textarea-positioned")).not.toMatch(/z-index/);
    });
  });

  describe("typo checker rules carry no z-index", () => {
    it.each([
      ".ai-helper-typo-overlay",
      ".ai-helper-typo-overlay-active",
      ".ai-helper-typo-overlay-scrollable",
      ".ai-helper-typo-control-panel",
      ".ai-helper-control-panel-positioned",
    ])("%s has no z-index", (selector) => {
      expect(getRuleBody(selector)).not.toMatch(/z-index/);
    });
  });
});
