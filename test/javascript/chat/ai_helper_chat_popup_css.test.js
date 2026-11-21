import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { normalize, parseRules } from "../support/css_rules.js";

/**
 * Reads the plugin stylesheet and parses it.
 * @returns {ReturnType<typeof parseRules>} the rules
 */
function loadRules() {
  // Vitest runs with the plugin root as the working directory
  return parseRules(readFileSync(resolve(process.cwd(), "assets/stylesheets/ai_helper.css"), "utf8"));
}

const POPUP = "#aihelper-sidebar.aihelper-popup-mode";
const POPUP_UNDER_MODAL = "body:has(.ui-widget-overlay) #aihelper-sidebar.aihelper-popup-mode";

describe("chat popup CSS contract (ui-contract.md, FR-001, FR-003, FR-007, FR-008, FR-010, FR-011, FR-018, R-006)", () => {
  const rules = loadRules();

  /**
   * Finds the rules whose selector list contains the selector exactly.
   * @param {string} selector normalized selector
   * @param {string|null} [media] the enclosing media query; null for none
   * @returns {ReturnType<typeof parseRules>} matching rules
   */
  function findRules(selector, media = null) {
    return rules.filter((rule) => rule.selectors.includes(selector) && rule.media === media);
  }

  /**
   * Returns the value of a declaration of the one rule that has the selector.
   * @param {string} selector normalized selector
   * @param {string} property declaration name
   * @param {string|null} [media] the enclosing media query; null for none
   * @returns {string|undefined} the normalized value
   */
  function declared(selector, property, media = null) {
    const found = findRules(selector, media).filter((rule) => rule.declarations[property] !== undefined);
    expect(found, `${selector} ${property}`).toHaveLength(1);
    return found[0].declarations[property];
  }

  const subjectOf = (selector) => selector.split(/[\s>+~]+/).filter(Boolean).pop();

  describe("popup mode", () => {
    it("is fixed to the viewport", () => {
      expect(declared(POPUP, "position")).toBe("fixed");
    });

    it("shows the close button and the resize handles, and hides the fold arrow and the open icon", () => {
      expect(declared(`${POPUP} #aihelper-popup-close`, "display")).toBe("inline-block");
      expect(declared(`${POPUP} .aihelper-popup-resize`, "display")).toBe("block");
      expect(declared(`${POPUP} .aihelper-arrow-button`, "display")).toBe("none");
      expect(declared(`${POPUP} #aihelper-popup-open`, "display")).toBe("none");
    });

    it("keeps the conversation and form visible when the sidebar was folded", () => {
      expect(declared(`${POPUP} #aihelper-foldable-area`, "display")).toBe("flex !important");
    });

    it("hides the popup-only controls while the chat is in the sidebar", () => {
      const hidden = findRules("#aihelper-popup-close");

      expect(hidden.some((rule) => rule.selectors.includes(".aihelper-popup-resize") && rule.declarations.display === "none")).toBe(true);
    });

    it("positions every resize handle at its own edge or corner", () => {
      ["n", "s", "e", "w", "ne", "nw", "se", "sw"].forEach((edge) => {
        expect(findRules(`.aihelper-popup-resize[data-edge="${edge}"]`), edge).toHaveLength(1);
      });
      expect(declared(".aihelper-popup-resize", "position")).toBe("absolute");
    });

    it("lets touch drags reach the pointer handlers", () => {
      const touch = rules.filter((rule) => rule.declarations["touch-action"] === "none");

      expect(touch.flatMap((rule) => rule.selectors)).toEqual(expect.arrayContaining([`${POPUP} .aihelper-header`, ".aihelper-popup-resize"]));
    });

    it("is not printed", () => {
      expect(declared(POPUP, "display", "print")).toBe("none");
    });

    it("animates opening and closing (FR-018, FR-019) with left, top, width and height over 200ms", () => {
      expect(declared("#aihelper-sidebar.aihelper-popup-animating", "transition")).toBe("left 200ms,top 200ms,width 200ms,height 200ms");
    });

    it("keeps the copied sidebar list and divider rules below the plugin's own conversation rules", () => {
      const copies = rules.flatMap((rule) => rule.selectors).filter((selector) => selector.includes("aihelper-popup-mode") && /(^|\s)(ul|li|hr)$/.test(selector));

      // Guards against passing vacuously: the ul, ul li, hr and dropdown copies exist
      expect(copies.length).toBeGreaterThanOrEqual(4);
      copies.forEach((selector) => expect(selector, "specificity must stay below #aihelper-chat-conversation ul li").toMatch(/^:where\(/));
    });
  });

  describe("narrow screens (FR-001, R-009)", () => {
    it("hides the open icon at 899px and below, the same query the script asks for", () => {
      const script = readFileSync(resolve(process.cwd(), "assets/javascripts/chat/ai_helper_chat_popup.js"), "utf8");
      const query = script.match(/NARROW_QUERY = '([^']+)'/);

      expect(query, "NARROW_QUERY not found in the script").not.toBeNull();
      expect(declared("#aihelper-popup-open", "display", normalize(query[1]))).toBe("none");
    });
  });

  describe("flash prevention (R-005)", () => {
    it("hides the chat with visibility, so it can still be measured", () => {
      expect(declared("html.aihelper-popup-pending #aihelper-sidebar", "visibility")).toBe("hidden");
    });
  });

  describe("stacking and non-modal behaviour (FR-010, FR-011, R-006)", () => {
    it("puts the popup above Redmine's sticky issue header (z-index 1000)", () => {
      expect(declared(POPUP, "z-index")).toBe("1001");
    });

    it("lowers the popup below Redmine's modal dialog (.ui-front, z-index 100) while a modal overlay is open", () => {
      expect(declared(POPUP_UNDER_MODAL, "z-index")).toBe("90");
    });

    it("keeps the popup below the plugin's own overlays and tooltips (z-index 9998 and above)", () => {
      const popupZ = Number(declared(POPUP, "z-index"));
      const pluginOverlays = rules.filter((rule) => Number(rule.declarations["z-index"]) >= 9998);

      expect(pluginOverlays.length).toBeGreaterThan(0);
      expect(popupZ).toBeLessThan(9998);
    });

    it("declares nothing that blocks or covers the page behind the popup", () => {
      const popupRules = rules.filter((rule) => rule.selectors.some((selector) => /aihelper-popup|aihelper-sidebar/.test(selector)));
      const subjectRules = popupRules.filter((rule) => rule.selectors.some((selector) => subjectOf(selector).includes("aihelper-sidebar")));
      const coverProperties = ["pointer-events", "backdrop-filter", "inset", "inset-block", "inset-inline", "inset-block-start", "inset-block-end", "inset-inline-start", "inset-inline-end"];
      const sizeProperties = ["width", "height", "min-width", "min-height", "max-width", "max-height", "inline-size", "block-size", "min-inline-size", "min-block-size", "max-inline-size", "max-block-size"];
      const viewportSize = /100(vw|vh|vmin|vmax|%)|100[sld]v[wh]|100[sld]vmin|100[sld]vmax/;

      // Guards against the checks below passing because the scan found nothing
      expect(findRules(POPUP).length).toBeGreaterThan(0);
      expect(popupRules.length).toBeGreaterThan(5);
      expect(subjectRules.length).toBeGreaterThan(0);
      popupRules.forEach((rule) => {
        const label = rule.selectors.join(",");
        coverProperties.forEach((property) => expect(rule.declarations[property], `${label} declares ${property}`).toBeUndefined());
        rule.selectors.forEach((selector) => expect(selector).not.toContain("::backdrop"));
      });
      subjectRules.forEach((rule) => {
        const label = rule.selectors.join(",");
        sizeProperties.forEach((property) => expect(rule.declarations[property] || "", `${label} ${property}`).not.toMatch(viewportSize));
        const offsets = ["top", "right", "bottom", "left"].map((side) => rule.declarations[side]);
        expect(offsets.every((value) => value === "0" || value === "0px"), `${label} stretches over the viewport`).toBe(false);
      });
    });

    it("only styles the chat element, never html, body or a bare class, when keyed on popup state", () => {
      const keyed = rules.flatMap((rule) => rule.selectors).filter((selector) => /aihelper-popup-pending|ui-widget-overlay/.test(selector));

      // Guards against passing vacuously: the pending rule and the under-modal rule exist
      expect(keyed.length).toBeGreaterThanOrEqual(2);
      keyed.forEach((selector) => {
        expect(subjectOf(selector), selector).toContain("aihelper-sidebar");
      });
    });
  });
});
