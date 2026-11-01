import { beforeEach, describe, expect, it } from "vitest";
import { loadScript } from "../support/load_script.js";

const VIEWPORT = { width: 1024, height: 768 };

describe("AiHelperChatPopupLayout", () => {
  let layout;

  beforeEach(async () => {
    await loadScript("assets/javascripts/chat/ai_helper_chat_popup_layout");
    layout = window.AiHelperChatPopupLayout;
  });

  describe("isValid", () => {
    it("accepts four finite numbers with a positive size", () => {
      expect(layout.isValid({ left: -5, top: 0, width: 300, height: 400 })).toBe(true);
    });

    it.each([
      ["null", null],
      ["a string", "x"],
      ["missing left", { top: 1, width: 300, height: 300 }],
      ["a string number", { left: "1", top: 1, width: 300, height: 300 }],
      ["null value", { left: null, top: 1, width: 300, height: 300 }],
      ["zero width", { left: 1, top: 1, width: 0, height: 300 }],
      ["negative height", { left: 1, top: 1, width: 300, height: -5 }],
      ["NaN", { left: NaN, top: 1, width: 300, height: 300 }],
      ["Infinity", { left: 1, top: 1, width: Infinity, height: 300 }],
    ])("rejects %s", (_name, value) => {
      expect(layout.isValid(value)).toBe(false);
    });
  });

  describe("clamp", () => {
    it("raises a too-small size to 240x240", () => {
      expect(layout.clamp({ left: 10, top: 10, width: 100, height: 50 }, VIEWPORT)).toEqual({ left: 10, top: 10, width: 240, height: 240 });
    });

    it("shrinks an oversized layout to the viewport", () => {
      expect(layout.clamp({ left: 0, top: 0, width: 2000, height: 2000 }, VIEWPORT)).toEqual({ left: 0, top: 0, width: 1024, height: 768 });
    });

    it("moves a layout that overflows the viewport back inside", () => {
      expect(layout.clamp({ left: 900, top: 700, width: 300, height: 300 }, VIEWPORT)).toEqual({ left: 724, top: 468, width: 300, height: 300 });
      expect(layout.clamp({ left: -50, top: -20, width: 300, height: 300 }, VIEWPORT)).toEqual({ left: 0, top: 0, width: 300, height: 300 });
    });

    it("prefers the minimum size over a viewport smaller than it, and never goes negative", () => {
      expect(layout.clamp({ left: 50, top: 50, width: 300, height: 300 }, { width: 200, height: 150 })).toEqual({ left: 0, top: 0, width: 240, height: 240 });
    });
  });

  describe("resized", () => {
    const start = { left: 100, top: 100, width: 300, height: 300 };

    it.each([
      { edge: "e", expected: { left: 100, top: 100, width: 340, height: 300 } },
      { edge: "w", expected: { left: 140, top: 100, width: 260, height: 300 } },
      { edge: "s", expected: { left: 100, top: 100, width: 300, height: 340 } },
      { edge: "n", expected: { left: 100, top: 140, width: 300, height: 260 } },
    ])("the $edge edge moves only itself", ({ edge, expected }) => {
      expect(layout.resized(start, edge, { x: 40, y: 40 }, VIEWPORT)).toEqual(expected);
    });

    it("keeps the minimum size even when the viewport is shorter than it", () => {
      const tall = { left: 0, top: 0, width: 300, height: 240 };

      expect(layout.resized(tall, "s", { x: 0, y: 100 }, { width: 1024, height: 200 }).height).toBe(240);
      expect(layout.resized(tall, "n", { x: 0, y: 50 }, { width: 1024, height: 200 })).toMatchObject({ top: 0, height: 240 });
    });

    it("stops at the viewport edges", () => {
      expect(layout.resized(start, "se", { x: 5000, y: 5000 }, VIEWPORT)).toEqual({ left: 100, top: 100, width: 924, height: 668 });
    });
  });

  describe("moved", () => {
    it("keeps the size and stays inside the viewport", () => {
      const start = { left: 100, top: 100, width: 300, height: 300 };

      expect(layout.moved(start, { x: 40, y: -30 }, VIEWPORT)).toEqual({ left: 140, top: 70, width: 300, height: 300 });
      expect(layout.moved(start, { x: 900, y: 900 }, VIEWPORT)).toEqual({ left: 724, top: 468, width: 300, height: 300 });
    });
  });
});
