import { describe, expect, it } from "vitest";
import { parseRules } from "./css_rules.js";

describe("parseRules (test helper)", () => {
  it("reads declarations and the enclosing media query", () => {
    const rules = parseRules("a, b { color: red; z-index: 3 } @media (max-width: 899px) { c { top: 0 } }");

    expect(rules[0]).toEqual({ selectors: ["a", "b"], declarations: { color: "red", "z-index": "3" }, media: null });
    expect(rules[1].media).toBe("(max-width: 899px)");
  });

  it("lower-cases property names so a lookup cannot miss an upper-case spelling", () => {
    expect(parseRules("a { Z-INDEX: 3 }")[0].declarations).toEqual({ "z-index": "3" });
  });

  it("splits the top-level commas of a selector that has parentheses", () => {
    expect(parseRules(":not(.a) b, c:not(.d) { e: f }")[0].selectors).toEqual([":not(.a) b", "c:not(.d)"]);
  });

  it("skips @keyframes blocks", () => {
    const rules = parseRules("@keyframes k { 0% { a: b } 100% { a: c } } d { e: f }");

    expect(rules).toHaveLength(1);
    expect(rules[0].selectors).toEqual(["d"]);
  });

  it.each([
    ["an unsupported at-rule", "@supports (display: grid) { a { b: c } }"],
    ["an unbalanced closing brace", "a { b: c } }"],
    ["an unclosed @media block", "@media print { a { b: c }"],
    ["text without a block", "a { b: c } stray"],
    ["a nested rule", "a { b { c: d } }"],
    ["an unclosed @keyframes block", "@keyframes k { 0% { a: b }"],
    ["an unclosed style rule", "a { b: c"],
    ["a declaration without a colon", "a { garbage; b: c }"],
    ["a comma inside :is()", "a:is(b, c) { d: e }"],
    ["a comma inside :has()", "body:has(.a, .b) c { d: e }"],
    ["url() in a value", "a { b: url(data:x;y) }"],
    ["a nested @media", "@media print { @media (min-width: 1px) { a { b: c } } }"],
    ["a comma inside nested parentheses", ":is(:not(.a), .b) { c: d }"],
    ["a comma after a closed group inside parentheses", ":is(:not(.a) .b, .c) { d: e }"],
    ["unbalanced parentheses in a selector", "a:is(b { c: d }"],
    ["a property declared twice in one rule", "a { background: #fff; background: var(--oc-gray-0) }"],
    ["a property declared twice with different case", "a { Color: red; color: blue }"],
    ["var(--oc-*) inside @keyframes", "@keyframes k { 0% { color: var(--oc-gray-9, #333) } }"],
    ["var(--oc-*) with a space inside @keyframes", "@keyframes k { 0% { color: var( --oc-gray-9, #333) } }"],
    ["upper-case VAR(--oc-*) inside @keyframes", "@keyframes k { 0% { color: VAR(--oc-gray-9, #333) } }"],
  ])("throws on %s", (_name, source) => {
    expect(() => parseRules(source)).toThrow();
  });
});
