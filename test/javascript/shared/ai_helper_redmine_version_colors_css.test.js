import { describe, expect, it } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import { normalize, parseRules } from "../support/css_rules.js";
import { findOpenColorVars, hasFallback, resolveForRedmine6, resolveForRedmine7 } from "../support/open_color_vars.js";

const STYLESHEET_DIR = resolve(process.cwd(), "assets/stylesheets");
const stylesheets = readdirSync(STYLESHEET_DIR).filter((name) => name.endsWith(".css"));
const sources = Object.fromEntries(stylesheets.map((name) => [name, readFileSync(resolve(STYLESHEET_DIR, name), "utf8")]));

const POPUP = "#aihelper-sidebar.aihelper-popup-mode";
const APPLY_BTN = ".ai-helper-reply-apply-btn";

/**
 * The contract table (specs/087-fix-popup-oc-colors/contracts/css-color-contract.md).
 * Every declaration of ai_helper.css that uses var(--oc-*) is listed here.
 */
const CONTRACT = [
  { selector: APPLY_BTN, property: "color", redmine7: "var(--oc-gray-9)", redmine6: "#333" },
  { selector: APPLY_BTN, property: "background-color", redmine7: "var(--oc-white)", redmine6: "#fff" },
  { selector: APPLY_BTN, property: "border", redmine7: "1px solid var(--oc-gray-4)", redmine6: "1px solid #ccc" },
  { selector: `${APPLY_BTN}:hover`, property: "background-color", redmine7: "var(--oc-gray-2)", redmine6: "#ddd" },
  { selector: `${APPLY_BTN}:active`, property: "background-color", redmine7: "var(--oc-gray-3)", redmine6: "#ddd" },
  { selector: POPUP, property: "background", redmine7: "var(--oc-gray-0)", redmine6: "#f9fafb" },
  { selector: POPUP, property: "border", redmine7: "1px solid var(--oc-gray-4)", redmine6: "1px solid #d0d7de" },
  { selector: POPUP, property: "box-shadow", redmine7: "0 2px 6px rgba(var(--oc-black-rgb), 0.15)", redmine6: "0 2px 6px rgba(0, 0, 0, 0.15)" },
  { selector: `:where(${POPUP}) hr`, property: "background", redmine7: "var(--oc-gray-4)", redmine6: "#ccc" },
];

/**
 * Collects the declarations of ai_helper.css that use var(--oc-*).
 * @returns {{selector: string, property: string, value: string}[]} one entry per selector and property
 */
function collectOpenColorDeclarations() {
  const rules = parseRules(sources["ai_helper.css"]);
  const collected = [];
  rules.forEach((rule) => {
    Object.entries(rule.declarations).forEach(([property, value]) => {
      if (/var\(\s*--oc-/i.test(value)) {
        rule.selectors.forEach((selector) => collected.push({ selector, property, value }));
      }
    });
  });
  return collected;
}

describe("Open Color variables in the plugin stylesheets (FR-001 to FR-004, FR-006)", () => {
  const declarations = collectOpenColorDeclarations();

  it("uses var(--oc-*) only in the declarations of the contract table", () => {
    const key = (entry) => `${entry.selector} | ${entry.property}`;

    expect(declarations.map(key).sort()).toEqual(CONTRACT.map(key).sort());
  });

  describe.each(CONTRACT)("$selector $property", ({ selector, property, redmine7, redmine6 }) => {
    const found = declarations.filter((entry) => entry.selector === selector && entry.property === property);

    it("is found in ai_helper.css", () => {
      expect(found).toHaveLength(1);
    });

    it("resolves to the unchanged Redmine 7 value", () => {
      expect(found).toHaveLength(1);
      expect(normalize(resolveForRedmine7(found[0].value))).toBe(normalize(redmine7));
    });

    it("has the Redmine 6 value", () => {
      expect(found).toHaveLength(1);
      expect(normalize(resolveForRedmine6(found[0].value))).toBe(normalize(redmine6));
    });
  });

  it("gives every var(--oc-*) of every stylesheet a non-empty fallback", () => {
    expect(stylesheets).toContain("ai_helper.css");
    const occurrences = stylesheets.flatMap((name) => findOpenColorVars(sources[name]).map((entry) => ({ file: name, ...entry })));

    expect(occurrences.filter((entry) => entry.file === "ai_helper.css").length).toBeGreaterThanOrEqual(CONTRACT.length);
    const withoutFallback = occurrences.filter((entry) => !hasFallback(entry));
    expect(withoutFallback).toEqual([]);
  });
});
