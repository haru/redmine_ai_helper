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

    // Fence and whitespace boundary rules, the same inputs as the Ruby
    // Scanner tests ("fenced code blocks" and "boundary rules shared with
    // the JS scanner" in scanner_test.rb).
    const D = "{{ai_helper_chart(status, version=12)}}";
    const boundaryCases = [
      { name: "keeps a directive inside a fence with an info string", input: `\`\`\`ruby\n${D}\n\`\`\``, expected: `\`\`\`ruby\n${D}\n\`\`\`` },
      { name: "keeps a directive inside an unclosed fence until the end", input: `~~~\n${D}\nmore`, expected: `~~~\n${D}\nmore` },
      { name: "does not close a fence with a shorter closing line", input: `\`\`\`\`\n${D}\n\`\`\`\nmore\n\`\`\`\``, expected: `\`\`\`\`\n${D}\n\`\`\`\nmore\n\`\`\`\`` },
      { name: "allows up to three leading spaces on a fence line", input: ` \`\`\`\n${D}\n \`\`\``, expected: ` \`\`\`\n${D}\n \`\`\`` },
      { name: "closes a tilde fence with a tilde line", input: `~~~\ntext\n~~~\n${D}`, expected: "~~~\ntext\n~~~" },
      { name: "does not open a backtick fence whose info string has a backtick", input: `\`\`\`a\`b\n${D}`, expected: "```a`b" },
      { name: "does not close a fence with text after the fence", input: `\`\`\`\n\`\`\` x\n${D}\n\`\`\``, expected: `\`\`\`\n\`\`\` x\n${D}\n\`\`\`` },
      { name: "does not treat a four-space fence line as a fence", input: `    \`\`\`\n${D}`, expected: "    ```" },
      { name: "keeps a directive with a leading tab", input: `\t${D}`, expected: `\t${D}` },
      { name: "removes a directive with a trailing tab", input: `${D}\t`, expected: "" },
    ];

    for (const c of boundaryCases) {
      it(c.name, () => {
        expect(window.AiHelperChartDirective.stripForStreaming(c.input)).toBe(c.expected);
      });
    }

    // CommonMark HTML blocks of types 1-5, the same inputs as the Ruby
    // Scanner tests ("raw HTML blocks (CommonMark types 1-5)" in
    // scanner_test.rb): a directive inside them is raw HTML content and is
    // kept.
    const htmlBlockCases = [
      { name: "keeps a directive inside a pre block", input: `Intro\n\n<pre>\n${D}\n</pre>\n`, expected: `Intro\n\n<pre>\n${D}\n</pre>\n` },
      { name: "keeps a directive inside an HTML comment", input: `<!--\n${D}\n-->`, expected: `<!--\n${D}\n-->` },
      ...[["<script>", "</script>"], ["<style>", "</style>"], ["<textarea>", "</textarea>"]].map(([open, close]) => ({
        name: `keeps a directive inside a ${open} block`,
        input: `${open}\n${D}\n${close}`,
        expected: `${open}\n${D}\n${close}`,
      })),
      ...[["<?php", "?>"], ["<!DOCTYPE", "html>"], ["<![CDATA[", "]]>"]].map(([open, close]) => ({
        name: `keeps a directive inside a block opened by ${open}`,
        input: `${open}\n${D}\n${close}`,
        expected: `${open}\n${D}\n${close}`,
      })),
      { name: "keeps a directive after an unterminated HTML block until the end", input: `<pre>\n${D}`, expected: `<pre>\n${D}` },
      { name: "closes the HTML block on its opening line when it ends there", input: `<pre>code</pre>\n${D}`, expected: "<pre>code</pre>" },
      { name: "removes a directive after the HTML block closed", input: `<pre>\ncode\n</pre>\n\n${D}`, expected: "<pre>\ncode\n</pre>\n" },
      { name: "does not open an HTML block inside a fenced code block", input: `\`\`\`\n<pre>\n${D}\n</pre>\n\`\`\`\n${D}`, expected: `\`\`\`\n<pre>\n${D}\n</pre>\n\`\`\`` },
      { name: "does not open a fenced code block inside an HTML block", input: `<pre>\n\`\`\`\n${D}\n\`\`\`\n</pre>`, expected: `<pre>\n\`\`\`\n${D}\n\`\`\`\n</pre>` },
      { name: "does not leave a fence open after a comment that contains a fence line", input: `<!--\n\`\`\`\n-->\n${D}`, expected: "<!--\n```\n-->" },
      { name: "treats uppercase opening tags like lowercase ones", input: `<PRE>\n${D}\n</PRE>`, expected: `<PRE>\n${D}\n</PRE>` },
      { name: "does not treat a lookalike tag as an HTML block", input: `<preview>\n${D}`, expected: "<preview>" },
      { name: "still removes a directive between the blank lines of a type 6 block", input: `<details>\n\n${D}\n\n</details>`, expected: "<details>\n\n\n</details>" },
      { name: "does not hide a directive prefix still arriving inside an HTML block", input: "<pre>\n{{ai_he", expected: "<pre>\n{{ai_he" },
    ];

    for (const c of htmlBlockCases) {
      it(c.name, () => {
        expect(window.AiHelperChartDirective.stripForStreaming(c.input)).toBe(c.expected);
      });
    }

    describe("trailing line still being received", () => {
      [
        ["a single brace", "text\n{", "text"],
        ["a prefix after three spaces", "text\n   {{ai", "text"],
        ["a prefix after four spaces (indented code)", "text\n    {{ai", "text\n    {{ai"],
        ["a prefix inside a fence", "```\n{{ai_he", "```\n{{ai_he"],
      ].forEach(([name, input, expected]) => {
        it(`handles ${name}`, () => {
          expect(window.AiHelperChartDirective.stripForStreaming(input)).toBe(expected);
        });
      });
    });

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

    it("does not touch a directive inside an HTML block", () => {
      const markdown = "<pre>\n{{ai_helper_chart(status, version=12)}}\n</pre>\n<!--\n{{ai_helper_chart(status, version=12)}}\n-->";

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
