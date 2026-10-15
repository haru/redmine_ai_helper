import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Collapses whitespace and drops it around `>`, `,`, `(` and `)`, so that
 * selectors, values and media queries compare equal regardless of formatting.
 * @param {string} text a selector, declaration value or media query
 * @returns {string} the normalized text
 */
function normalize(text) {
  return text.replace(/\s+/g, " ").replace(/\s*([>,()])\s*/g, "$1").trim();
}

// Scope prefix of the dashboard-only rules (contracts/dashboard_health_report_layout.md)
const D = "body.controller-ai_helper_dashboard.action-index";
const NARROW = normalize("screen and (max-width: 900px)");
const PANE = `${D} .ai-helper-detail-pane`;
const FRAME = `${D} .ai-helper-project-health-content.has-report`;
// Media filter of findRules that matches rules inside and outside any @media block
const ANY_MEDIA = Symbol("any media");

/**
 * Reads the plugin stylesheet from disk.
 * @returns {string} the CSS source
 */
function readCss() {
  // Vitest runs with the plugin root as the working directory
  return readFileSync(resolve(process.cwd(), "assets/stylesheets/ai_helper.css"), "utf8");
}

/**
 * Splits a stylesheet into its innermost rules and records the @media query
 * each one sits in. This is a lightweight scan, not a CSS parser: jsdom cannot
 * compute layout, so the layout contract is checked at the source level.
 * @param {string} source CSS source, comments allowed
 * @returns {{selectors: string[], body: string, media: (string|null)}[]} each
 *   rule's normalized selector list, declaration block and enclosing media query
 */
function parseRules(source) {
  const css = source.replace(/\/\*[\s\S]*?\*\//g, "");
  const rules = [];
  const re = /([^{}]*)\{|\}/g;
  let media = null;
  let match;
  while ((match = re.exec(css)) !== null) {
    if (match[0] === "}") {
      // Rules and @keyframes consume their own closing brace, so this one closes @media
      media = closeMedia(media, match.index);
      continue;
    }
    const step = readBlock(css, { prelude: match[1].trim(), start: re.lastIndex, media });
    if (step.rule) {
      rules.push(step.rule);
    }
    media = step.media;
    re.lastIndex = step.next;
  }
  if (media !== null) {
    throw new Error(`Unclosed @media block: ${media}`);
  }
  return rules;
}

/**
 * Reads the block that a prelude opens: enters an @media block, skips a
 * @keyframes block, or reads a rule. Any other at-rule raises, because the
 * scan could not tell which conditions its rules apply under.
 * @param {string} css CSS source without comments
 * @param {{prelude: string, start: number, media: (string|null)}} block the text
 *   before the opening brace (trimmed), the index just after the brace and the
 *   enclosing media query
 * @returns {{media: (string|null), next: number, rule: (object|undefined)}} the
 *   media query in effect afterwards, the index to resume at and the rule read
 */
function readBlock(css, { prelude, start, media }) {
  if (prelude.startsWith("@keyframes")) {
    return { media, next: endOfBlock(css, start) };
  }
  if (prelude.startsWith("@media")) {
    return { media: openMedia(prelude, media), next: start };
  }
  if (prelude.startsWith("@")) {
    throw new Error(`Unsupported at-rule: ${prelude}`);
  }
  const next = endOfBlock(css, start);
  const body = css.slice(start, next - 1);
  if (body.includes("{")) {
    throw new Error(`Nested rule is not supported in: ${prelude}`);
  }
  return { media, next, rule: { selectors: splitTopLevel(prelude).map(normalize), body, media } };
}

/**
 * Enters an @media block.
 * @param {string} prelude the @media prelude
 * @param {(string|null)} media the enclosing media query
 * @returns {string} the normalized media query
 */
function openMedia(prelude, media) {
  if (media !== null) {
    throw new Error(`Nested @media is not supported: ${prelude}`);
  }
  return normalize(prelude.replace(/^@media\s+/, ""));
}

/**
 * Leaves an @media block.
 * @param {(string|null)} media the media query being closed
 * @param {number} offset position of the closing brace, for the error message
 * @returns {null} no media query
 */
function closeMedia(media, offset) {
  if (media === null) {
    throw new Error(`Unbalanced "}" at offset ${offset}`);
  }
  return null;
}

// Nesting depth change per bracket character
const BRACE_DELTA = { "{": 1, "}": -1 };
const PAREN_DELTA = { "(": 1, "[": 1, ")": -1, "]": -1 };

/**
 * Finds the end of the block whose opening brace precedes `start`.
 * @param {string} css CSS source without comments
 * @param {number} start index just after the opening brace
 * @returns {number} index just after the matching closing brace
 */
function endOfBlock(css, start) {
  let depth = 1;
  for (let i = start; i < css.length; i += 1) {
    depth += BRACE_DELTA[css[i]] ?? 0;
    if (depth === 0) {
      return i + 1;
    }
  }
  throw new Error(`Unclosed block at offset ${start}`);
}

/**
 * Splits a selector list at the commas outside parentheses and brackets,
 * so `:is(a, b)` stays one selector.
 * @param {string} prelude a rule's selector list
 * @returns {string[]} the selectors, untrimmed
 */
function splitTopLevel(prelude) {
  const parts = [];
  let depth = 0;
  let from = 0;
  for (let i = 0; i < prelude.length; i += 1) {
    depth += PAREN_DELTA[prelude[i]] ?? 0;
    if (prelude[i] === "," && depth === 0) {
      parts.push(prelude.slice(from, i));
      from = i + 1;
    }
  }
  parts.push(prelude.slice(from));
  return parts;
}

/**
 * Converts a declaration block into a property map.
 * @param {string} body declaration block without braces
 * @returns {Object<string, string>} property to normalized value; `!important` stays in the value
 */
function declarationsOf(body) {
  const result = {};
  body.split(";").forEach((decl) => {
    const idx = decl.indexOf(":");
    if (idx === -1) {
      return;
    }
    result[decl.slice(0, idx).trim()] = normalize(decl.slice(idx + 1));
  });
  return result;
}

/**
 * Merges the declarations of several rules in source order: a later value
 * wins unless the earlier one is `!important` and the later one is not.
 * @param {Object<string, string>[]} maps declaration maps in source order
 * @returns {Object<string, string>} merged declarations
 */
function merge(maps) {
  const important = (value) => value !== undefined && value.endsWith("!important");
  const result = {};
  maps.forEach((map) => {
    Object.entries(map).forEach(([prop, value]) => {
      if (!important(result[prop]) || important(value)) {
        result[prop] = value;
      }
    });
  });
  return result;
}

const RULES = parseRules(readCss());

/**
 * Finds the rules of the plugin stylesheet whose selector list contains the selector.
 * @param {string} selector a single selector; compared after normalization
 * @param {{media: (string|null|symbol)}} [options] the media query the rule must
 *   sit in: null = outside any, ANY_MEDIA (default) = anywhere
 * @returns {Object<string, string>[]} declaration maps of the matching rules
 */
function findRules(selector, { media = ANY_MEDIA } = {}) {
  const target = normalize(selector);
  return RULES
    .filter((rule) => media === ANY_MEDIA || rule.media === media)
    .filter((rule) => rule.selectors.includes(target))
    .map((rule) => declarationsOf(rule.body));
}

/**
 * Asserts that a rule neither caps the height nor hides overflowing content.
 * @param {Object<string, string>} decls declaration map of one rule
 * @returns {void}
 */
function expectNoClipping(decls) {
  expect(decls["max-height"]).toBeUndefined();
  ["overflow", "overflow-x", "overflow-y"].forEach((prop) => {
    expect(decls[prop] ?? "").not.toMatch(/\b(hidden|clip)\b/);
  });
}

describe("CSS scan helpers", () => {
  it("records the media query of a rule and leaves the rules after the block outside it", () => {
    const rules = parseRules("@media screen and (max-width: 10px) { .a { color: red } } .b { color: blue }");
    expect(rules.map((rule) => [rule.selectors[0], rule.media])).toEqual([
      [".a", normalize("screen and (max-width: 10px)")],
      [".b", null],
    ]);
  });

  it("skips @keyframes bodies", () => {
    const rules = parseRules("@keyframes spin { from { opacity: 0 } to { opacity: 1 } } .a { color: red }");
    expect(rules.map((rule) => [rule.selectors[0], rule.media])).toEqual([[".a", null]]);
  });

  it("throws on an at-rule it cannot attribute", () => {
    expect(() => parseRules("@supports (display: grid) { .a { max-height: 1px } }")).toThrow(/@supports/);
  });

  it("throws on a nested @media block", () => {
    expect(() => parseRules("@media print { @media (min-width: 1px) { .a { color: red } } }")).toThrow(/Nested @media/);
  });

  it("splits a selector list only at top-level commas", () => {
    expect(parseRules(":is(.a, .b) .c, .d { color: red }")[0].selectors).toEqual([normalize(":is(.a, .b) .c"), ".d"]);
  });

  it("compares selectors and values regardless of spacing around combinators and parentheses", () => {
    const [rule] = parseRules(".a:has( >.b ) { max-height: max( 1em,calc(1vh - 2px) ) }");
    expect(rule.selectors).toEqual([normalize(".a:has(> .b)")]);
    expect(declarationsOf(rule.body)["max-height"]).toBe(normalize("max(1em, calc(1vh - 2px))"));
  });

  it("keeps an !important value over a later normal one when merging", () => {
    expect(merge([{ height: "auto !important" }, { height: "300px" }]).height).toBe("auto !important");
    expect(merge([{ height: "auto" }, { height: "300px" }]).height).toBe("300px");
  });
});

describe("unchanged unscoped rules (C-3)", () => {
  it("keeps the detail page frame fixed at 480px", () => {
    const decls = merge(findRules(".ai-helper-project-health-content.has-report", { media: null }));
    expect(decls.height).toBe("480px !important");
    expect(decls["overflow-y"]).toBe("scroll !important");
  });
});

describe("dashboard detail pane (width > 900px)", () => {
  it("does not clip the pane and lets it wrap its content (C-1.1)", () => {
    findRules(PANE).forEach(expectNoClipping);
    expect(merge(findRules(PANE, { media: null }))["align-self"]).toBe("flex-start");
  });

  it("does not clip the detail container, detail or body (C-1.2)", () => {
    [
      `${D} #ai-helper-health-report-detail-container`,
      `${D} .ai-helper-health-report-detail`,
      `${D} .ai-helper-health-report-body`,
    ].forEach((selector) => {
      findRules(selector).forEach(expectNoClipping);
    });
  });

  it("caps the report frame by the viewport height (C-1.3)", () => {
    const decls = merge(findRules(FRAME, { media: null }));
    expect(decls["min-height"]).toBe("17em");
    expect(decls.height).toBe("auto !important");
    expect(decls["max-height"]).toBe(normalize("max(17em, calc(100vh - 340px - 14em))"));
    expect(decls["overflow-y"]).toBe("auto !important");
  });
});

describe("dashboard edit form state", () => {
  it("lifts the frame cap while the edit form is open (C-1.4)", () => {
    const selector = `${FRAME}:has(> .ai-helper-health-report-edit-form:not([hidden]))`;
    const decls = merge(findRules(selector, { media: null }));
    expect(decls["max-height"]).toBe("none");
  });
});

describe("dashboard detail pane (width <= 900px)", () => {
  it("returns the pane to normal alignment (C-2.1)", () => {
    expect(merge(findRules(PANE, { media: NARROW }))["align-self"]).toBe("auto");
  });

  it("restores the pre-fix frame sizing (C-2.2)", () => {
    const decls = merge(findRules(FRAME, { media: NARROW }));
    expect(decls["min-height"]).toBe("360px");
    expect(decls["max-height"]).toBe("none");
  });

  it("no longer carries cancelling rules for the removed containers (R-006)", () => {
    // Guards against a vacuous pass: the narrow block itself must be found
    expect(findRules(PANE, { media: NARROW })).not.toEqual([]);
    [
      `${D} #ai-helper-health-report-detail-container`,
      `${D} .ai-helper-health-report-detail`,
    ].forEach((selector) => {
      expect(findRules(selector, { media: NARROW })).toEqual([]);
    });
  });
});
