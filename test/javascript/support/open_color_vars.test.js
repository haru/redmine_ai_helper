import { describe, expect, it } from "vitest";
import { findOpenColorVars, hasFallback, resolveForRedmine6, resolveForRedmine7 } from "./open_color_vars.js";

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
    ["whitespace after var(", "color: var( --oc-gray-9, #333)"],
    ["a newline after var(", "color: var(\n  --oc-gray-9, #333)"],
    ["upper-case VAR(", "color: VAR(--oc-gray-9, #333)"],
  ])("finds a variable written with %s", (_name, source) => {
    expect(findOpenColorVars(source)).toEqual([{ name: "--oc-gray-9", fallback: "#333" }]);
  });

  it("finds a variable without a fallback written with whitespace", () => {
    expect(findOpenColorVars("var( --oc-gray-9 )")).toEqual([{ name: "--oc-gray-9", fallback: null }]);
  });

  it("accepts whitespace before the comma", () => {
    expect(findOpenColorVars("var(--oc-gray-9 , #333)")).toEqual([{ name: "--oc-gray-9", fallback: "#333" }]);
  });

  it("ignores a variable that is only mentioned in a comment", () => {
    expect(findOpenColorVars("/* was var(--oc-gray-4) */ a { b: c }")).toEqual([]);
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

describe("hasFallback (test helper)", () => {
  it.each([
    ["a fallback", { fallback: "#333" }, true],
    ["no fallback", { fallback: null }, false],
    ["an empty fallback", { fallback: "" }, false],
  ])("is decided for %s", (_name, entry, expected) => {
    expect(hasFallback(entry)).toBe(expected);
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

  it("resolves the spellings that findOpenColorVars finds", () => {
    expect(resolveForRedmine6("VAR( --oc-gray-4 , #ccc)")).toBe("#ccc");
    expect(resolveForRedmine7("VAR( --oc-gray-4 , #ccc)")).toBe("var(--oc-gray-4)");
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
