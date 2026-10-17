import { beforeEach, describe, expect, it } from "vitest";
import { loadScript } from "../support/load_script.js";

describe("AiHelperChartDirective", () => {
  beforeEach(async () => {
    delete window.AiHelperChartDirective;
    await loadScript("assets/javascripts/project_health/ai_helper_chart_directive");
  });

  describe("stripForStreaming", () => {
    // Same inputs and expectations as the Ruby Scanner tests
    // (test/unit/lib/health_report_chart/scanner_test.rb): the judgment
    // table #1-#13 of contracts/chart-directive.md, plus the
    // streaming-only trailing-line cases #14 and #15.
    const cases = [
      { id: 1, name: "removes a full directive line", input: "{{ai_helper_chart(status, version=12)}}", expected: "" },
      {
        id: 2,
        name: "removes a directive with indentation and trailing spaces",
        input: "   {{ai_helper_chart(tracker,period=last_week)}}  ",
        expected: "",
      },
      {
        id: 3,
        name: "keeps a line indented with four spaces (indented code block)",
        input: "    {{ai_helper_chart(status, version=12)}}",
        expected: "    {{ai_helper_chart(status, version=12)}}",
      },
      {
        id: 4,
        name: "keeps an unclosed directive line that ends with a newline",
        input: "{{ai_helper_chart(status, version=12)\n",
        expected: "{{ai_helper_chart(status, version=12)\n",
      },
      {
        id: 5,
        name: "keeps a directive inside inline code",
        input: "`{{ai_helper_chart(status, version=12)}}`",
        expected: "`{{ai_helper_chart(status, version=12)}}`",
      },
      {
        id: 6,
        name: "keeps a directive in a list item",
        input: "- {{ai_helper_chart(status, version=12)}}",
        expected: "- {{ai_helper_chart(status, version=12)}}",
      },
      {
        id: 7,
        name: "keeps a directive in a block quote",
        input: "> {{ai_helper_chart(status, version=12)}}",
        expected: "> {{ai_helper_chart(status, version=12)}}",
      },
      {
        id: 8,
        name: "keeps a directive inside a fenced code block",
        input: "```\n{{ai_helper_chart(status, version=12)}}\n```",
        expected: "```\n{{ai_helper_chart(status, version=12)}}\n```",
      },
      {
        id: 9,
        name: "keeps directives inside a tilde fence opened before a backtick fence",
        input: "~~~~\n{{ai_helper_chart(status, version=12)}}\n```\n{{ai_helper_chart(tracker, period=last_week)}}\n~~~~",
        expected: "~~~~\n{{ai_helper_chart(status, version=12)}}\n```\n{{ai_helper_chart(tracker, period=last_week)}}\n~~~~",
      },
      { id: 10, name: "removes a directive with invalid arguments", input: "{{ai_helper_chart(status)}}", expected: "" },
      {
        id: 11,
        name: "removes a directive with a malformed version target",
        input: "{{ai_helper_chart(status, version=abc)}}",
        expected: "",
      },
      {
        id: 12,
        name: "removes a directive with an unknown chart type",
        input: "{{ai_helper_chart(burndown, version=12)}}",
        expected: "",
      },
      {
        id: 13,
        name: "removes a directive between text lines without blank lines",
        input: "text\n{{ai_helper_chart(status, version=12)}}\ntext",
        expected: "text\ntext",
      },
      {
        id: 14,
        name: "hides a trailing partial directive prefix while streaming",
        input: "text\n{{ai_he",
        expected: "text",
      },
      {
        id: 15,
        name: "shows a trailing line that is not a directive prefix",
        input: "text\n{ is a brace",
        expected: "text\n{ is a brace",
      },
      {
        id: 16,
        name: "hides a trailing unclosed directive still being received",
        input: "{{ai_helper_chart(status, version=12)",
        expected: "",
      },
    ];

    for (const c of cases) {
      it(`#${c.id} ${c.name}`, () => {
        expect(window.AiHelperChartDirective.stripForStreaming(c.input)).toBe(c.expected);
      });
    }

    it("returns a body without directives unchanged", () => {
      const markdown = "# Heading\n\nBody with **bold** text.";

      expect(window.AiHelperChartDirective.stripForStreaming(markdown)).toBe(markdown);
    });

    it("removes several directive lines and keeps the text between them", () => {
      const markdown = "text\n{{ai_helper_chart(status, version=12)}}\nmid\n{{ai_helper_chart(bar, period=all_time)}}\nend";

      expect(window.AiHelperChartDirective.stripForStreaming(markdown)).toBe("text\nmid\nend");
    });

    it("removes a trailing complete directive line that ends with a newline", () => {
      const markdown = "text\n{{ai_helper_chart(status, version=12)}}\n";

      expect(window.AiHelperChartDirective.stripForStreaming(markdown)).toBe("text\n");
    });
  });
  describe("replaceForComparison", () => {
    const message = "Charts cannot be drawn in a comparison report";

    it("replaces a directive line with the message surrounded by blank lines", () => {
      const markdown = "text\n{{ai_helper_chart(status, version=12)}}\nend";

      expect(window.AiHelperChartDirective.replaceForComparison(markdown, message))
        .toBe(`text\n\n${message}\n\nend`);
    });

    it("replaces every directive and leaves a body without directives unchanged", () => {
      const two = "{{ai_helper_chart(status, version=12)}}\n\n{{ai_helper_chart(tracker, period=all_time)}}";

      expect(window.AiHelperChartDirective.replaceForComparison(two, message))
        .toBe(`\n${message}\n\n\n\n${message}\n`);
      expect(window.AiHelperChartDirective.replaceForComparison("plain\ntext", message)).toBe("plain\ntext");
    });

    it("does not touch a directive inside a fenced code block or an indented one", () => {
      const markdown = "```\n{{ai_helper_chart(status, version=12)}}\n```\n    {{ai_helper_chart(status, version=12)}}";

      expect(window.AiHelperChartDirective.replaceForComparison(markdown, message)).toBe(markdown);
    });

    it("replaces a directive with invalid arguments too", () => {
      expect(window.AiHelperChartDirective.replaceForComparison("{{ai_helper_chart(status)}}", message))
        .toBe(`\n${message}\n`);
    });

    [ undefined, null, "", 5, {} ].forEach((bad) => {
      it(`throws a TypeError when the message is ${JSON.stringify(bad) ?? "undefined"}`, () => {
        expect(() => window.AiHelperChartDirective.replaceForComparison("text", bad)).toThrow(TypeError);
      });
    });
  });
});
