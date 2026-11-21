import { describe, expect, it } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import { normalize, parseRules } from "../support/css_rules.js";

const OPEN_COLOR_VAR = "var(--oc-";

/**
 * Parses the `var(--oc-NAME[, fallback])` that starts at `start`.
 * @param {string} source text containing the var() call
 * @param {number} start offset of `var(--oc-`
 * @returns {{name: string, fallback: (string|null), start: number, end: number}} the call; `end` is just after the closing parenthesis
 */
function parseOpenColorVar(source, start) {
  const nameStart = start + OPEN_COLOR_VAR.length;
  const name = /^[A-Za-z0-9-]+/.exec(source.slice(nameStart));
  if (name === null) {
    throw new Error(`Missing variable name at offset ${start}`);
  }
  const afterName = nameStart + name[0].length;
  if (source[afterName] === ")") {
    return { name: `--oc-${name[0]}`, fallback: null, start, end: afterName + 1 };
  }
  if (source[afterName] !== ",") {
    throw new Error(`Expected "," or ")" after --oc-${name[0]} at offset ${afterName}`);
  }
  let depth = 1;
  for (let i = afterName + 1; i < source.length; i += 1) {
    depth += { "(": 1, ")": -1 }[source[i]] || 0;
    if (depth === 0) {
      return { name: `--oc-${name[0]}`, fallback: source.slice(afterName + 1, i).trim(), start, end: i + 1 };
    }
  }
  throw new Error(`Unclosed var() at offset ${start}`);
}

/**
 * Finds every `var(--oc-NAME ...)` in a text, including the ones nested in a
 * fallback.
 * @param {string} source CSS text
 * @returns {{name: string, fallback: (string|null)}[]} the occurrences, `fallback` is null when there is none
 */
export function findOpenColorVars(source) {
  const found = [];
  let index = source.indexOf(OPEN_COLOR_VAR);
  while (index !== -1) {
    const parsed = parseOpenColorVar(source, index);
    found.push({ name: parsed.name, fallback: parsed.fallback });
    index = source.indexOf(OPEN_COLOR_VAR, index + OPEN_COLOR_VAR.length);
  }
  return found;
}

/**
 * Resolves a value as Redmine 6 does: every `var(--oc-*, fallback)` becomes
 * its fallback, because Redmine 6 defines no `--oc-*` variable.
 * @param {string} value a declaration value
 * @returns {string} the value with the fallbacks in place
 * @throws {Error} when a `var(--oc-*)` has no or an empty fallback
 */
export function resolveForRedmine6(value) {
  let resolved = value;
  let index = resolved.indexOf(OPEN_COLOR_VAR);
  while (index !== -1) {
    const parsed = parseOpenColorVar(resolved, index);
    if (parsed.fallback === null || parsed.fallback === "") {
      throw new Error(`${parsed.name} has no fallback in: ${value}`);
    }
    resolved = resolved.slice(0, parsed.start) + parsed.fallback + resolved.slice(parsed.end);
    index = resolved.indexOf(OPEN_COLOR_VAR);
  }
  return resolved;
}

/**
 * Resolves a value as Redmine 7 does: the variable is defined, so every
 * fallback is ignored and `var(--oc-NAME, fallback)` is `var(--oc-NAME)`.
 * @param {string} value a declaration value
 * @returns {string} the value with the fallbacks removed
 */
export function resolveForRedmine7(value) {
  let resolved = "";
  let cursor = 0;
  let index = value.indexOf(OPEN_COLOR_VAR);
  while (index !== -1) {
    const parsed = parseOpenColorVar(value, index);
    resolved += `${value.slice(cursor, parsed.start)}var(${parsed.name})`;
    cursor = parsed.end;
    index = value.indexOf(OPEN_COLOR_VAR, cursor);
  }
  return resolved + value.slice(cursor);
}

describe("findOpenColorVars (test helper)", () => {
  it("returns the fallback of a variable that has one", () => {
    expect(findOpenColorVars("color: var(--oc-gray-9, #333)")).toEqual([{ name: "--oc-gray-9", fallback: "#333" }]);
  });

  it("returns null for a variable without a fallback", () => {
    expect(findOpenColorVars("color: var(--oc-gray-9)")).toEqual([{ name: "--oc-gray-9", fallback: null }]);
  });

  it("keeps the commas of a fallback", () => {
    expect(findOpenColorVars("rgba(var(--oc-black-rgb, 0, 0, 0), 0.15)")).toEqual([{ name: "--oc-black-rgb", fallback: "0, 0, 0" }]);
  });

  it("finds several variables in one value", () => {
    expect(findOpenColorVars("1px solid var(--oc-gray-4, #ccc) var(--oc-white)").map((v) => v.name)).toEqual(["--oc-gray-4", "--oc-white"]);
  });

  it("finds a variable nested in a fallback", () => {
    expect(findOpenColorVars("var(--oc-a, var(--oc-b))").map((v) => v.fallback)).toEqual(["var(--oc-b)", null]);
  });

  it("reports an empty fallback as an empty string", () => {
    expect(findOpenColorVars("var(--oc-a,)")).toEqual([{ name: "--oc-a", fallback: "" }]);
  });

  it.each([
    ["a missing closing parenthesis", "color: var(--oc-gray-9, #333"],
    ["a missing closing parenthesis without a fallback", "color: var(--oc-gray-9"],
    ["a missing variable name", "color: var(--oc-)"],
    ["text after the name that is not a comma or parenthesis", "color: var(--oc-gray-9 #333)"],
  ])("throws on %s", (_name, source) => {
    expect(() => findOpenColorVars(source)).toThrow();
  });
});

describe("resolveForRedmine6 / resolveForRedmine7 (test helpers)", () => {
  it("uses the fallback for Redmine 6, commas included", () => {
    expect(resolveForRedmine6("0 2px 6px rgba(var(--oc-black-rgb, 0, 0, 0), 0.15)")).toBe("0 2px 6px rgba(0, 0, 0, 0.15)");
  });

  it("resolves several variables in one value", () => {
    expect(resolveForRedmine6("1px solid var(--oc-gray-4, #ccc)")).toBe("1px solid #ccc");
    expect(resolveForRedmine6("var(--oc-a, #111) var(--oc-b, #222)")).toBe("#111 #222");
  });

  it("resolves a variable nested in a fallback", () => {
    expect(resolveForRedmine6("var(--oc-a, var(--oc-b, #444))")).toBe("#444");
  });

  it("returns a value without a variable unchanged", () => {
    expect(resolveForRedmine6("1px solid #ccc")).toBe("1px solid #ccc");
    expect(resolveForRedmine7("1px solid #ccc")).toBe("1px solid #ccc");
  });

  it.each([
    ["no fallback", "var(--oc-gray-9)"],
    ["an empty fallback", "var(--oc-gray-9,)"],
    ["no fallback on a nested variable", "var(--oc-a, var(--oc-b))"],
    ["a missing closing parenthesis", "var(--oc-a, #333"],
  ])("throws for Redmine 6 on %s", (_name, value) => {
    expect(() => resolveForRedmine6(value)).toThrow();
  });

  it("removes the fallbacks for Redmine 7", () => {
    expect(resolveForRedmine7("1px solid var(--oc-gray-4, #ccc)")).toBe("1px solid var(--oc-gray-4)");
    expect(resolveForRedmine7("0 2px 6px rgba(var(--oc-black-rgb, 0, 0, 0), 0.15)")).toBe("0 2px 6px rgba(var(--oc-black-rgb), 0.15)");
    expect(resolveForRedmine7("var(--oc-a, var(--oc-b, #444))")).toBe("var(--oc-a)");
  });

  it("leaves a value that has no fallback as it is for Redmine 7", () => {
    expect(resolveForRedmine7("var(--oc-gray-9)")).toBe("var(--oc-gray-9)");
  });
});

const STYLESHEET_DIR = resolve(process.cwd(), "assets/stylesheets");
const stylesheets = readdirSync(STYLESHEET_DIR).filter((name) => name.endsWith(".css"));

/**
 * The contract table (specs/087-fix-popup-oc-colors/contracts/css-color-contract.md).
 * Every declaration of ai_helper.css that uses var(--oc-*) is listed here.
 */
const POPUP = "#aihelper-sidebar.aihelper-popup-mode";
const CONTRACT = [
  { selector: ".ai-helper-reply-apply-btn", property: "color", redmine7: "var(--oc-gray-9)", redmine6: "#333" },
  { selector: ".ai-helper-reply-apply-btn", property: "background-color", redmine7: "var(--oc-white)", redmine6: "#fff" },
  { selector: ".ai-helper-reply-apply-btn", property: "border", redmine7: "1px solid var(--oc-gray-4)", redmine6: "1px solid #ccc" },
  { selector: ".ai-helper-reply-apply-btn:hover", property: "background-color", redmine7: "var(--oc-gray-2)", redmine6: "#ddd" },
  { selector: ".ai-helper-reply-apply-btn:active", property: "background-color", redmine7: "var(--oc-gray-3)", redmine6: "#ddd" },
  { selector: POPUP, property: "background", redmine7: "var(--oc-gray-0)", redmine6: "#f9fafb" },
  { selector: POPUP, property: "border", redmine7: "1px solid var(--oc-gray-4)", redmine6: "1px solid #d0d7de" },
  { selector: POPUP, property: "box-shadow", redmine7: "0 2px 6px rgba(var(--oc-black-rgb),0.15)", redmine6: "0 2px 6px rgba(0,0,0,0.15)" },
  { selector: `:where(${POPUP}) hr`, property: "background", redmine7: "var(--oc-gray-4)", redmine6: "#ccc" },
];

/**
 * Collects the declarations of ai_helper.css that use var(--oc-*).
 * @returns {{selector: string, property: string, value: string}[]} one entry per selector and property
 */
function collectOpenColorDeclarations() {
  const rules = parseRules(readFileSync(resolve(STYLESHEET_DIR, "ai_helper.css"), "utf8"));
  const collected = [];
  rules.forEach((rule) => {
    Object.entries(rule.declarations).forEach(([property, value]) => {
      if (value.includes(OPEN_COLOR_VAR)) {
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

    it("keeps the Redmine 7 value of before the fix", () => {
      expect(normalize(resolveForRedmine7(found[0].value))).toBe(normalize(redmine7));
    });

    it("has the Redmine 6 value", () => {
      expect(normalize(resolveForRedmine6(found[0].value))).toBe(normalize(redmine6));
    });
  });

  it("gives every var(--oc-*) of every stylesheet a non-empty fallback", () => {
    expect(stylesheets).toContain("ai_helper.css");
    const occurrences = stylesheets.flatMap((name) => findOpenColorVars(readFileSync(resolve(STYLESHEET_DIR, name), "utf8")).map((entry) => ({ file: name, ...entry })));

    expect(occurrences.filter((entry) => entry.file === "ai_helper.css").length).toBeGreaterThanOrEqual(CONTRACT.length);
    const withoutFallback = occurrences.filter((entry) => entry.fallback === null || entry.fallback === "");
    expect(withoutFallback).toEqual([]);
  });
});
