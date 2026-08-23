import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScript } from "../support/load_script.js";

function createTypoCheckerDOM(textareaId = "issue_description") {
  const parent = document.createElement("div");
  parent.style.position = "relative";

  const textarea = document.createElement("textarea");
  textarea.id = textareaId;
  parent.appendChild(textarea);

  const controlPanelId = {
    "issue_description": "ai-helper-typo-control-panel-description",
    "issue_notes": "ai-helper-typo-control-panel-notes",
    "content_text": "ai-helper-typo-control-panel-wiki",
  }[textareaId];

  const controlPanel = document.createElement("div");
  controlPanel.id = controlPanelId;
  const applyAllBtn = document.createElement("button");
  applyAllBtn.className = "ai-helper-typo-apply-all-btn";
  controlPanel.appendChild(applyAllBtn);
  const closeBtn = document.createElement("button");
  closeBtn.className = "ai-helper-typo-close-btn";
  controlPanel.appendChild(closeBtn);
  parent.appendChild(controlPanel);

  const checkBtnId = {
    "issue_description": "ai-helper-typo-check-description-btn",
    "issue_notes": "ai-helper-typo-check-notes-btn",
    "content_text": "ai-helper-typo-check-wiki-btn",
  }[textareaId];

  const checkBtn = document.createElement("button");
  checkBtn.id = checkBtnId;
  checkBtn.innerHTML = '<svg></svg> Check';
  parent.appendChild(checkBtn);

  // Button templates needed by buildOverlayContent
  const acceptTemplate = document.createElement("span");
  acceptTemplate.className = "ai-helper-typo-accept-btn-template";
  acceptTemplate.innerHTML = "✓";
  document.body.appendChild(acceptTemplate);

  const rejectTemplate = document.createElement("span");
  rejectTemplate.className = "ai-helper-typo-reject-btn-template";
  rejectTemplate.innerHTML = "✗";
  document.body.appendChild(rejectTemplate);

  // CSRF meta tag
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "test-csrf-token";
  document.head.appendChild(meta);

  document.body.appendChild(parent);

  return { parent, textarea, controlPanel, checkBtn };
}

function createChecker(textarea, options = {}) {
  const checker = new window.AiHelperTypoChecker(textarea, {
    endpoint: "/ai_helper/issue/1/check_typos",
    debounceDelay: 0,
    minLength: 1,
    labels: {
      checkButton: "Check",
      checking: "Checking...",
      noSuggestions: "No typos found",
      errorOccurred: "An error occurred",
      correctionTooltip: "Suggested correction",
      acceptSuggestion: "Accept",
      dismissSuggestion: "Reject",
      applyFailed: "Failed to apply",
    },
    ...options,
  });
  return checker;
}

describe("AiHelperTypoChecker overlay", () => {
  let dom;
  let textarea;
  let checker;

  beforeEach(async () => {
    await loadScript("assets/javascripts/typo_checker/ai_helper_typo_checker");
    await loadScript("assets/javascripts/typo_checker/ai_helper_typo_suggestion_overlay");
    dom = createTypoCheckerDOM();
    textarea = dom.textarea;
    textarea.value = "";
  });

  afterEach(() => {
    if (checker && checker.overlay && checker.overlay.parentNode) {
      checker.overlay.remove();
    }
    document.querySelectorAll(
      ".ai-helper-typo-accept-btn-template, .ai-helper-typo-reject-btn-template"
    ).forEach((el) => el.remove());
    if (dom && dom.parent && dom.parent.parentNode) {
      dom.parent.remove();
    }
    const meta = document.querySelector('meta[name="csrf-token"]');
    if (meta) {meta.remove();}
    vi.unstubAllGlobals();
  });


  describe("updateSuggestionsAfterEdit", () => {
    it("shifts positions of suggestions after the edit position", () => {
      checker = createChecker(textarea);
      checker.suggestions = [
        { position: 5, original: "foo", corrected: "bar" },
        { position: 10, original: "baz", corrected: "qux" },
        { position: 3, original: "hello", corrected: "world" },
      ];

      checker.updateSuggestionsAfterEdit(5, 3, 5);

      expect(checker.suggestions[0].position).toBe(5);
      expect(checker.suggestions[1].position).toBe(12);
      expect(checker.suggestions[2].position).toBe(3);
    });

    it("does not shift positions before the edit position", () => {
      checker = createChecker(textarea);
      checker.suggestions = [
        { position: 2, original: "ab", corrected: "abcde" },
        { position: 10, original: "xy", corrected: "xyz" },
      ];

      checker.updateSuggestionsAfterEdit(5, 1, 1);

      expect(checker.suggestions[0].position).toBe(2);
      expect(checker.suggestions[1].position).toBe(10);
    });

    it("shifts negatively when replacement is shorter", () => {
      checker = createChecker(textarea);
      checker.suggestions = [
        { position: 10, original: "longword", corrected: "hi" },
      ];

      checker.updateSuggestionsAfterEdit(5, 2, 2);

      expect(checker.suggestions[0].position).toBe(10);
    });

    it("handles empty suggestions array", () => {
      checker = createChecker(textarea);
      checker.suggestions = [];
      checker.updateSuggestionsAfterEdit(5, 3, 5);
      expect(checker.suggestions).toEqual([]);
    });
  });

  describe("acceptSuggestion (by index)", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
    });

    it("applies a single suggestion to the textarea", () => {
      textarea.value = "hello wrld goodbye";
      checker.suggestions = [
        { position: 6, original: "wrld", corrected: "world" },
      ];

      checker.acceptSuggestion(0);

      expect(textarea.value).toBe("hello world goodbye");
      expect(checker.suggestions).toEqual([]);
    });

    it("triggers an input event after applying", () => {
      const listener = vi.fn();
      textarea.addEventListener("input", listener);
      textarea.value = "teh cat";
      checker.suggestions = [
        { position: 0, original: "teh", corrected: "the" },
      ];

      checker.acceptSuggestion(0);

      expect(listener).toHaveBeenCalledTimes(1);
    });

    it("does nothing for out-of-range index", () => {
      textarea.value = "hello world";
      checker.suggestions = [
        { position: 0, original: "hello", corrected: "hi" },
      ];

      checker.acceptSuggestion(5);

      expect(textarea.value).toBe("hello world");
    });

    it("updates positions of remaining suggestions after applying one", () => {
      textarea.value = "teh cat satz";
      checker.suggestions = [
        { position: 0, original: "teh", corrected: "the" },
        { position: 8, original: "satz", corrected: "sat" },
      ];

      checker.acceptSuggestion(0);

      expect(textarea.value).toBe("the cat satz");
      expect(checker.suggestions).toHaveLength(1);
      expect(checker.suggestions[0].position).toBe(8);
    });

    it("handles text mismatch by searching for correct position", () => {
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
      textarea.value = "hello world world";
      checker.suggestions = [
        { position: 6, original: "world", corrected: "earth" },
      ];

      checker.acceptSuggestion(0);

      expect(textarea.value).toBe("hello earth world");
      consoleError.mockRestore();
    });
  });

  describe("rejectSuggestion (by index)", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
    });

    it("removes the suggestion without changing textarea", () => {
      textarea.value = "hello world";
      checker.suggestions = [
        { position: 0, original: "hello", corrected: "hi" },
        { position: 6, original: "world", corrected: "earth" },
      ];

      checker.rejectSuggestion(0);

      expect(textarea.value).toBe("hello world");
      expect(checker.suggestions).toHaveLength(1);
      expect(checker.suggestions[0].original).toBe("world");
    });
  });

  describe("acceptSuggestionBySuggestion", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
    });

    it("finds and applies the matching suggestion object", () => {
      textarea.value = "teh cat";
      const suggestion = { position: 0, original: "teh", corrected: "the" };
      checker.suggestions = [suggestion];

      checker.acceptSuggestionBySuggestion(suggestion);

      expect(textarea.value).toBe("the cat");
      expect(checker.suggestions).toEqual([]);
    });

    it("does nothing when suggestion is not found", () => {
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
      textarea.value = "hello world";
      checker.suggestions = [
        { position: 0, original: "hello", corrected: "hi" },
      ];

      checker.acceptSuggestionBySuggestion({
        position: 99,
        original: "nope",
        corrected: "nope2",
      });

      expect(textarea.value).toBe("hello world");
      expect(checker.suggestions).toHaveLength(1);
      consoleError.mockRestore();
    });
  });

  describe("rejectSuggestionBySuggestion", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
    });

    it("removes the matching suggestion without changing textarea", () => {
      textarea.value = "teh cat";
      const suggestion = { position: 0, original: "teh", corrected: "the" };
      checker.suggestions = [suggestion];

      checker.rejectSuggestionBySuggestion(suggestion);

      expect(textarea.value).toBe("teh cat");
      expect(checker.suggestions).toEqual([]);
    });
  });

  describe("acceptAllSuggestions", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
    });

    it("applies all suggestions from end to beginning", () => {
      textarea.value = "teh qwick brwn fx";
      checker.suggestions = [
        { position: 0, original: "teh", corrected: "the" },
        { position: 4, original: "qwick", corrected: "quick" },
        { position: 10, original: "brwn", corrected: "brown" },
        { position: 15, original: "fx", corrected: "fox" },
      ];

      checker.acceptAllSuggestions();

      expect(textarea.value).toBe("the quick brown fox");
      expect(checker.suggestions).toEqual([]);
    });

    it("triggers an input event", () => {
      const listener = vi.fn();
      textarea.addEventListener("input", listener);
      textarea.value = "teh cat";
      checker.suggestions = [
        { position: 0, original: "teh", corrected: "the" },
      ];

      checker.acceptAllSuggestions();

      expect(listener).toHaveBeenCalledTimes(1);
    });

    it("does nothing with empty suggestions", () => {
      textarea.value = "hello world";
      checker.suggestions = [];

      checker.acceptAllSuggestions();

      expect(textarea.value).toBe("hello world");
    });

    it("skips suggestions where text no longer matches at position", () => {
      textarea.value = "teh cat";
      checker.suggestions = [
        { position: 0, original: "teh", corrected: "the" },
        { position: 4, original: "dog", corrected: "cat" },
      ];

      checker.acceptAllSuggestions();

      expect(textarea.value).toBe("the cat");
    });
  });

  describe("hideOverlay", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
    });

    it("clears overlay state", () => {
      checker.isOverlayVisible = true;
      checker.suggestions = [{ position: 0, original: "a", corrected: "b" }];
      textarea.classList.add("ai-helper-text-transparent");

      checker.hideOverlay();

      expect(checker.isOverlayVisible).toBe(false);
      expect(checker.suggestions).toEqual([]);
      expect(textarea.classList.contains("ai-helper-text-transparent")).toBe(false);
    });

    it("removes active and scrollable classes from overlay", () => {
      checker.overlay.classList.add("ai-helper-typo-overlay-active");
      checker.overlay.classList.add("ai-helper-typo-overlay-scrollable");

      checker.hideOverlay();

      expect(
        checker.overlay.classList.contains("ai-helper-typo-overlay-active")
      ).toBe(false);
      expect(
        checker.overlay.classList.contains("ai-helper-typo-overlay-scrollable")
      ).toBe(false);
    });

    it("removes positioned class from control panel", () => {
      checker.controlPanel.classList.add("ai-helper-control-panel-positioned");

      checker.hideOverlay();

      expect(
        checker.controlPanel.classList.contains(
          "ai-helper-control-panel-positioned"
        )
      ).toBe(false);
    });
  });

  describe("showNoSuggestionsMessage", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
      checker.overlay.classList.add("ai-helper-typo-overlay-active");
      vi.useFakeTimers();
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    it("shows no-typos message and hides after timeout", () => {
      checker.showNoSuggestionsMessage();

      expect(checker.overlay.innerHTML).toContain("No typos found");
      expect(
        checker.overlay.classList.contains("ai-helper-typo-overlay-active")
      ).toBe(true);

      vi.advanceTimersByTime(3000);

      expect(
        checker.overlay.classList.contains("ai-helper-typo-overlay-active")
      ).toBe(false);
    });

    it("uses custom label", () => {
      checker.options.labels.noSuggestions = "All good!";
      checker.showNoSuggestionsMessage();

      expect(checker.overlay.innerHTML).toContain("All good!");
    });
  });

  describe("showErrorMessage", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
      vi.useFakeTimers();
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    it("shows error message and hides after timeout", () => {
      checker.showErrorMessage();

      expect(checker.overlay.innerHTML).toContain("An error occurred");
      expect(
        checker.overlay.classList.contains("ai-helper-typo-overlay-active")
      ).toBe(true);

      vi.advanceTimersByTime(3000);

      expect(
        checker.overlay.classList.contains("ai-helper-typo-overlay-active")
      ).toBe(false);
    });

    it("uses custom label", () => {
      checker.options.labels.errorOccurred = "Something broke";
      checker.showErrorMessage();

      expect(checker.overlay.innerHTML).toContain("Something broke");
    });
  });

  describe("buildOverlayContent", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
    });

    it("validates and corrects suggestion positions", () => {
      textarea.value = "hello world";
      checker.suggestions = [
        { position: 0, original: "hello", corrected: "hi", confidence: "high" },
      ];

      checker.buildOverlayContent();

      const typoSpans =
        checker.overlay.querySelectorAll(".ai-helper-typo-original");
      expect(typoSpans).toHaveLength(1);
      expect(typoSpans[0].textContent).toContain("hello");

      const correctionSpans = checker.overlay.querySelectorAll(
        ".ai-helper-typo-correction"
      );
      expect(correctionSpans).toHaveLength(1);
      expect(correctionSpans[0].textContent).toBe("hi");
    });

    it("filters out invalid suggestions", () => {
      textarea.value = "hello world";
      checker.suggestions = [
        { position: -1, original: "hello", corrected: "hi" },
        { position: 0, original: "hello", corrected: "hi" },
      ];

      checker.buildOverlayContent();

      const typoSpans =
        checker.overlay.querySelectorAll(".ai-helper-typo-original");
      expect(typoSpans).toHaveLength(1);
    });

    it("filters out suggestions missing original or corrected", () => {
      textarea.value = "hello world";
      checker.suggestions = [
        { position: 0, original: "notfound", corrected: "hi" },
        { position: 0, original: "hello", corrected: null },
      ];

      checker.buildOverlayContent();

      const typoSpans =
        checker.overlay.querySelectorAll(".ai-helper-typo-original");
      expect(typoSpans).toHaveLength(0);
    });

    it("corrects position when text does not match at expected position", () => {
      textarea.value = "world hello world";
      checker.suggestions = [
        { position: 6, original: "world", corrected: "earth" },
      ];

      checker.buildOverlayContent();

      expect(checker.suggestions).toHaveLength(1);
      // Position 6 has "hello", not "world". Should find "world" at position 0
      expect(checker.suggestions[0].position).toBe(0);
    });

    it("filters out suggestions whose original text is not found", () => {
      textarea.value = "hello world";
      checker.suggestions = [
        { position: 0, original: "notfound", corrected: "found" },
      ];

      checker.buildOverlayContent();

      expect(checker.suggestions).toHaveLength(0);
    });

    it("groups duplicate suggestions at same position", () => {
      textarea.value = "teh cat";
      checker.suggestions = [
        {
          position: 0,
          original: "teh",
          corrected: "the",
          reason: "spelling",
        },
        {
          position: 0,
          original: "teh",
          corrected: "the",
          reason: "common mistake",
        },
      ];

      checker.buildOverlayContent();

      expect(checker.suggestions).toHaveLength(1);
      expect(checker.suggestions[0].reasons).toContain("spelling");
      expect(checker.suggestions[0].reasons).toContain("common mistake");
    });

    it("handles reasons array in suggestions", () => {
      textarea.value = "teh cat";
      checker.suggestions = [
        {
          position: 0,
          original: "teh",
          corrected: "the",
          reasons: ["spelling", "grammar"],
        },
      ];

      checker.buildOverlayContent();

      expect(checker.suggestions).toHaveLength(1);
      expect(checker.suggestions[0].reasons).toEqual(["spelling", "grammar"]);
    });

    it("creates accept and reject buttons for each suggestion", () => {
      textarea.value = "teh cat";
      checker.suggestions = [
        { position: 0, original: "teh", corrected: "the" },
      ];

      checker.buildOverlayContent();

      const acceptBtns =
        checker.overlay.querySelectorAll(".ai-helper-typo-accept-btn");
      const rejectBtns =
        checker.overlay.querySelectorAll(".ai-helper-typo-reject-btn");
      expect(acceptBtns).toHaveLength(1);
      expect(rejectBtns).toHaveLength(1);
    });

    it("renders text segments between suggestions", () => {
      textarea.value = "hello teh world";
      checker.suggestions = [
        { position: 6, original: "teh", corrected: "the" },
      ];

      checker.buildOverlayContent();

      const textSpans =
        checker.overlay.querySelectorAll(".ai-helper-text-black");
      expect(textSpans).toHaveLength(2);
      expect(textSpans[0].textContent).toBe("hello ");
      expect(textSpans[1].textContent).toBe(" world");
    });
  });

  describe("displayTypoOverlay", () => {
    beforeEach(() => {
      checker = createChecker(textarea);
      checker.init();
    });

    it("shows no-suggestions message when suggestions are empty", () => {
      checker.suggestions = [];
      vi.useFakeTimers();

      checker.displayTypoOverlay();

      expect(
        checker.overlay.classList.contains("ai-helper-typo-overlay-active")
      ).toBe(true);
      expect(checker.overlay.innerHTML).toContain("No typos found");

      vi.useRealTimers();
    });

    it("shows overlay with suggestions", () => {
      textarea.value = "teh cat";
      checker.suggestions = [
        { position: 0, original: "teh", corrected: "the" },
      ];

      checker.displayTypoOverlay();

      expect(
        checker.overlay.classList.contains("ai-helper-typo-overlay-active")
      ).toBe(true);
      expect(checker.isOverlayVisible).toBe(true);
      expect(
        textarea.classList.contains("ai-helper-text-transparent")
      ).toBe(true);
    });
  });

  describe("static validateAndGroupSuggestions", () => {
    it("returns grouped suggestions for valid input", () => {
      const result = window.AiHelperTypoChecker.validateAndGroupSuggestions(
        [{ position: 0, original: "teh", corrected: "the" }],
        "teh cat"
      );
      expect(result).toHaveLength(1);
      expect(result[0].original).toBe("teh");
      expect(result[0].corrected).toBe("the");
    });

    it("filters out suggestions with negative position", () => {
      const result = window.AiHelperTypoChecker.validateAndGroupSuggestions(
        [{ position: -1, original: "a", corrected: "b" }],
        "abc"
      );
      expect(result).toHaveLength(0);
    });

    it("filters out suggestions where position exceeds text length", () => {
      const result = window.AiHelperTypoChecker.validateAndGroupSuggestions(
        [{ position: 10, original: "a", corrected: "b" }],
        "abc"
      );
      expect(result).toHaveLength(0);
    });

    it("groups duplicate suggestions at same position", () => {
      const result = window.AiHelperTypoChecker.validateAndGroupSuggestions(
        [
          { position: 0, original: "teh", corrected: "the", reason: "spelling" },
          { position: 0, original: "teh", corrected: "the", reason: "common" },
        ],
        "teh cat"
      );
      expect(result).toHaveLength(1);
      expect(result[0].reasons).toEqual(["spelling", "common"]);
    });

    it("deduplicates reasons", () => {
      const result = window.AiHelperTypoChecker.validateAndGroupSuggestions(
        [
          { position: 0, original: "teh", corrected: "the", reason: "spelling" },
          { position: 0, original: "teh", corrected: "the", reason: "spelling" },
        ],
        "teh cat"
      );
      expect(result).toHaveLength(1);
      expect(result[0].reasons).toEqual(["spelling"]);
    });

    it("handles reasons array on input", () => {
      const result = window.AiHelperTypoChecker.validateAndGroupSuggestions(
        [
          { position: 0, original: "teh", corrected: "the", reasons: ["a", "b"] },
        ],
        "teh cat"
      );
      expect(result).toHaveLength(1);
      expect(result[0].reasons).toEqual(["a", "b"]);
    });

    it("corrects position to closest match", () => {
      const result = window.AiHelperTypoChecker.validateAndGroupSuggestions(
        [{ position: 8, original: "cat", corrected: "dog" }],
        "the cat sat"
      );
      expect(result).toHaveLength(1);
      expect(result[0].position).toBe(4);
    });

    it("sorts suggestions by position", () => {
      const result = window.AiHelperTypoChecker.validateAndGroupSuggestions(
        [
          { position: 8, original: "sat", corrected: "sat on" },
          { position: 0, original: "teh", corrected: "the" },
        ],
        "teh cat sat"
      );
      expect(result[0].position).toBe(0);
      expect(result[1].position).toBe(8);
    });

    it("uses high confidence correction when grouping", () => {
      const result = window.AiHelperTypoChecker.validateAndGroupSuggestions(
        [
          { position: 0, original: "teh", corrected: "the", confidence: "low" },
          { position: 0, original: "teh", corrected: "tha", confidence: "high" },
        ],
        "teh cat"
      );
      expect(result).toHaveLength(1);
      expect(result[0].corrected).toBe("tha");
    });
  });

  describe("static applyAllSuggestionTexts", () => {
    it("applies all suggestions from end to beginning", () => {
      const result = window.AiHelperTypoChecker.applyAllSuggestionTexts(
        [
          { position: 0, original: "teh", corrected: "the" },
          { position: 4, original: "qwick", corrected: "quick" },
        ],
        "teh qwick fox"
      );
      expect(result).toBe("the quick fox");
    });

    it("skips suggestions where text does not match", () => {
      const result = window.AiHelperTypoChecker.applyAllSuggestionTexts(
        [
          { position: 0, original: "xxx", corrected: "the" },
          { position: 4, original: "qwick", corrected: "quick" },
        ],
        "teh qwick fox"
      );
      expect(result).toBe("teh quick fox");
    });

    it("returns original text for empty suggestions", () => {
      const result = window.AiHelperTypoChecker.applyAllSuggestionTexts(
        [], "hello world"
      );
      expect(result).toBe("hello world");
    });
  });

  describe("static updateSuggestionPositions", () => {
    it("shifts positions after edit position", () => {
      const result = window.AiHelperTypoChecker.updateSuggestionPositions(
        [
          { position: 5, original: "foo" },
          { position: 10, original: "bar" },
          { position: 3, original: "baz" },
        ],
        5, 3, 5
      );
      expect(result[0].position).toBe(5);
      expect(result[1].position).toBe(12);
      expect(result[2].position).toBe(3);
    });

    it("does not modify positions before edit position", () => {
      const result = window.AiHelperTypoChecker.updateSuggestionPositions(
        [{ position: 2, original: "a" }],
        5, 1, 1
      );
      expect(result[0].position).toBe(2);
    });

    it("returns new array without mutating input", () => {
      const input = [{ position: 10, original: "x" }];
      const result = window.AiHelperTypoChecker.updateSuggestionPositions(
        input, 5, 2, 4
      );
      expect(result).not.toBe(input);
      expect(input[0].position).toBe(10);
      expect(result[0].position).toBe(12);
    });
  });
});
