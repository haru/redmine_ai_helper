import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { loadScript } from "../support/load_script.js";

// Ported from the pre-existing (never-run) test/javascript/ai_helper_markdown_parser_test.js.
// Each case below preserves the verification intent of the corresponding
// assertion in that file.

describe("AiHelperMarkdownParser issue reference linkification", () => {
  beforeEach(async () => {
    delete window.ai_helper_urls;
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
  });

  afterEach(() => {
    delete window.ai_helper_urls;
  });

  function setupIssueBaseUrl(template) {
    window.ai_helper_urls = { issue_base: template };
  }

  it("linkifies #1234 after whitespace", () => {
    setupIssueBaseUrl("/issues/__ID__");
    const parser = new window.AiHelperMarkdownParser();
    const html = parser.parse("See #1234 please");
    expect(html).toContain('<a href="/issues/1234">#1234</a>');
  });

  it("uses the relative_url_root subpath in the href", () => {
    setupIssueBaseUrl("/redmine/issues/__ID__");
    const parser = new window.AiHelperMarkdownParser();
    const html = parser.parse("See #1234");
    expect(html).toContain('<a href="/redmine/issues/1234">#1234</a>');
  });

  it("linkifies #1234 at the start of a line (distinct from an H1 heading)", () => {
    setupIssueBaseUrl("/issues/__ID__");
    const parser = new window.AiHelperMarkdownParser();
    const html = parser.parse("#1234\nbody");
    expect(html).toMatch(/<a href="\/issues\/1234">#1234<\/a>/);
  });

  it("does not linkify markdown heading syntax", () => {
    setupIssueBaseUrl("/issues/__ID__");
    const parser = new window.AiHelperMarkdownParser();
    const html = parser.parse("# Heading\nbody");
    expect(html).toContain("<h1>Heading</h1>");
    expect(html).not.toContain('<a href="/issues/');
  });

  it("does not linkify when preceded by a word character", () => {
    setupIssueBaseUrl("/issues/__ID__");
    const parser = new window.AiHelperMarkdownParser();
    expect(parser.parse("abc#1234")).not.toContain('<a href="/issues/');
    expect(parser.parse("v1.0#1234")).not.toContain('<a href="/issues/1234');
    expect(parser.parse("my_var#1234")).not.toContain('<a href="/issues/');
  });

  it("does not linkify inside fenced code blocks", () => {
    setupIssueBaseUrl("/issues/__ID__");
    const parser = new window.AiHelperMarkdownParser();
    const html = parser.parse("```\nSee #1234\n```");
    expect(html).not.toContain('<a href="/issues/1234');
  });

  it("does not linkify inside inline code", () => {
    setupIssueBaseUrl("/issues/__ID__");
    const parser = new window.AiHelperMarkdownParser();
    const html = parser.parse("See `#1234` literal");
    expect(html).not.toContain('<a href="/issues/1234');
  });

  it("preserves existing markdown links without double-linking", () => {
    setupIssueBaseUrl("/issues/__ID__");
    const parser = new window.AiHelperMarkdownParser();
    const html = parser.parse("Old format: [#1234](/issues/1234)");
    const anchors = html.match(/<a /g) || [];
    expect(anchors).toHaveLength(1);
    expect(html).toContain('<a href="/issues/1234">#1234</a>');
  });

  it("linkifies multiple issue references", () => {
    setupIssueBaseUrl("/issues/__ID__");
    const parser = new window.AiHelperMarkdownParser();
    const html = parser.parse("See #100 and #200 and #100 again");
    const count = (html.match(/<a /g) || []).length;
    expect(count).toBe(3);
    expect(html).toContain('<a href="/issues/100">#100</a>');
    expect(html).toContain('<a href="/issues/200">#200</a>');
  });

  it("is a no-op when ai_helper_urls.issue_base is absent", () => {
    const parser = new window.AiHelperMarkdownParser();
    const html = parser.parse("See #1234");
    expect(html).not.toContain("<a href=");
  });

  it("linkifies an issue reference inside parentheses", () => {
    setupIssueBaseUrl("/issues/__ID__");
    const parser = new window.AiHelperMarkdownParser();
    const html = parser.parse("(see #1234)");
    expect(html).toContain('<a href="/issues/1234">#1234</a>');
  });

  it("does not linkify a non-digit id (XSS defense)", () => {
    setupIssueBaseUrl("/issues/__ID__");
    const parser = new window.AiHelperMarkdownParser();
    const html = parser.parse("See #abc");
    expect(html).not.toContain('<a href="/issues/');
  });

  it("terminates instead of hanging on an unterminated internal mask marker", () => {
    setupIssueBaseUrl("/issues/__ID__");
    const parser = new window.AiHelperMarkdownParser();
    // The internal masking delimiter is a NUL byte followed by "AIH_MASK_";
    // this input contains the opening marker with no matching closing NUL.
    const unterminated = "See #1234 and \x00AIH_MASK_0 with no closing marker";
    const html = parser.parse(unterminated);
    expect(html).toContain('<a href="/issues/1234">#1234</a>');
  });

  it("does not render 'undefined' for a mask marker with an out-of-range index", () => {
    setupIssueBaseUrl("/issues/__ID__");
    const parser = new window.AiHelperMarkdownParser();
    // A well-formed marker (both NUL delimiters present) but with an index
    // that was never actually masked -- there is nothing at masks[99].
    const bogus = "See #1234 and \x00AIH_MASK_99\x00 in the text";
    const html = parser.parse(bogus);
    expect(html).toContain('<a href="/issues/1234">#1234</a>');
    expect(html).not.toContain("undefined");
  });
});

describe("AiHelperMarkdownParser basic rendering", () => {
  let parser;

  beforeEach(async () => {
    delete window.ai_helper_urls;
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
    parser = new window.AiHelperMarkdownParser();
  });

  it("renders headings h1 through h6", () => {
    for (let level = 1; level <= 6; level++) {
      const hashes = "#".repeat(level);
      const html = parser.parse(`${hashes} Title ${level}`);
      expect(html).toContain(`<h${level}>Title ${level}</h${level}>`);
    }
  });

  it("renders bold and italic text", () => {
    expect(parser.parse("**bold**")).toContain("<strong>bold</strong>");
    expect(parser.parse("*italic*")).toContain("<em>italic</em>");
  });

  it("renders a link with a safe URL", () => {
    const html = parser.parse("[Redmine](https://www.redmine.org)");
    expect(html).toContain('<a href="https://www.redmine.org">Redmine</a>');
  });

  it("renders link text without a href when the URL is unsafe", () => {
    const html = parser.parse("[click me](javascript:alert(1))");
    expect(html).not.toContain("<a href");
    expect(html).toContain("click me");
  });

  it("renders inline code and fenced code blocks", () => {
    expect(parser.parse("`inline`")).toContain("<code>inline</code>");
    expect(parser.parse("```\nblock\n```")).toContain("<pre><code>");
  });

  it("wraps a plain text line in a paragraph", () => {
    expect(parser.parse("Just some text")).toContain("<p>Just some text</p>");
  });

  it("renders a simple unordered and ordered list", () => {
    const ul = parser.parse("- one\n- two");
    expect(ul).toContain("<ul>");
    expect(ul).toContain("<li>one");
    expect(ul).toContain("<li>two");
    expect(ul).toContain("</ul>");

    const ol = parser.parse("1. first\n2. second");
    expect(ol).toContain("<ol>");
    expect(ol).toContain("<li>first");
  });

  it("escapes raw HTML embedded in the source before applying markdown rules", () => {
    const html = parser.parse('<img src=x onerror="alert(1)">');
    expect(html).not.toContain("<img");
    expect(html).toContain("&lt;img");
  });
});

describe("AiHelperMarkdownParser.escapeHtml", () => {
  it("returns an empty string for null or undefined", () => {
    expect(window.AiHelperMarkdownParser.escapeHtml(null)).toBe("");
    expect(window.AiHelperMarkdownParser.escapeHtml(undefined)).toBe("");
  });

  it("escapes &, <, >, \", and '", () => {
    expect(window.AiHelperMarkdownParser.escapeHtml(`&<>"'`)).toBe("&amp;&lt;&gt;&quot;&#39;");
  });

  beforeEach(async () => {
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
  });
});

describe("AiHelperMarkdownParser.sanitizeUrl", () => {
  beforeEach(async () => {
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
  });

  it("allows http(s) and mailto URLs", () => {
    expect(window.AiHelperMarkdownParser.sanitizeUrl("https://example.com")).toBe("https://example.com");
    expect(window.AiHelperMarkdownParser.sanitizeUrl("http://example.com")).toBe("http://example.com");
    expect(window.AiHelperMarkdownParser.sanitizeUrl("mailto:a@example.com")).toBe("mailto:a@example.com");
  });

  it("allows relative, fragment, and query URLs", () => {
    expect(window.AiHelperMarkdownParser.sanitizeUrl("/issues/1")).toBe("/issues/1");
    expect(window.AiHelperMarkdownParser.sanitizeUrl("#section")).toBe("#section");
    expect(window.AiHelperMarkdownParser.sanitizeUrl("?q=1")).toBe("?q=1");
  });

  it("blocks javascript:, data:, and vbscript: URLs", () => {
    expect(window.AiHelperMarkdownParser.sanitizeUrl("javascript:alert(1)")).toBeNull();
    expect(window.AiHelperMarkdownParser.sanitizeUrl("data:text/html,x")).toBeNull();
    expect(window.AiHelperMarkdownParser.sanitizeUrl("vbscript:msgbox(1)")).toBeNull();
  });

  it("returns null for an empty or missing URL", () => {
    expect(window.AiHelperMarkdownParser.sanitizeUrl("")).toBeNull();
    expect(window.AiHelperMarkdownParser.sanitizeUrl(null)).toBeNull();
  });

  it("trims whitespace before validating", () => {
    expect(window.AiHelperMarkdownParser.sanitizeUrl("  https://example.com  ")).toBe("https://example.com");
  });
});

describe("AiHelperMarkdownParser sanitizeOutput", () => {
  let parser;

  beforeEach(async () => {
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
    parser = new window.AiHelperMarkdownParser();
  });

  it("strips script, iframe, object, embed, form, and base tags with their content", () => {
    const html = parser.sanitizeOutput(
      '<p>keep</p><script>alert(1)</script><iframe src="x"></iframe>' +
        '<object data="x"></object><embed src="x"><form></form><base href="x">',
    );
    expect(html).toContain("keep");
    expect(html).not.toContain("<script");
    expect(html).not.toContain("<iframe");
    expect(html).not.toContain("<object");
    expect(html).not.toContain("<embed");
    expect(html).not.toContain("<form");
    expect(html).not.toContain("<base");
  });

  it("removes on* event handler attributes from any element", () => {
    const html = parser.sanitizeOutput('<div onclick="alert(1)" data-keep="yes">text</div>');
    expect(html).not.toContain("onclick");
    expect(html).toContain('data-keep="yes"');
    expect(html).toContain("text");
  });
});

describe("AiHelperMarkdownParser tables", () => {
  let parser;

  beforeEach(async () => {
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
    parser = new window.AiHelperMarkdownParser();
  });

  it("renders a header-only table", () => {
    const html = parser.parse("|A|B|\n|---|---|");
    expect(html).toContain('<table class="list">');
    expect(html).toContain("<th>A</th>");
    expect(html).toContain("<th>B</th>");
    expect(html).not.toContain("<tbody>");
  });

  it("renders a table with body rows and column alignment", () => {
    const html = parser.parse("|Left|Center|Right|\n|:---|:---:|---:|\n|a|b|c|");
    expect(html).toContain('<th align="center">Center</th>');
    expect(html).toContain('<th align="right">Right</th>');
    expect(html).toContain("<th>Left</th>");
    expect(html).toContain('<td align="center">b</td>');
    expect(html).toContain('<td align="right">c</td>');
    expect(html).toContain("<td>a</td>");
  });

  it("renders a table that runs to the end of the document", () => {
    const html = parser.parse("Intro text\n\n|X|\n|---|\n|1|");
    expect(html).toContain("<table");
    expect(html).toContain("<td>1</td>");
  });
});

describe("AiHelperMarkdownParser nested and mixed lists", () => {
  let parser;

  beforeEach(async () => {
    await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
    parser = new window.AiHelperMarkdownParser();
  });

  it("nests a sub-list under a parent item", () => {
    const html = parser.parse("- parent\n  - child");
    expect(html).toContain("<ul>");
    expect(html).toContain("<li>parent");
    expect(html).toContain("<li>child");
    expect((html.match(/<\/ul>/g) || []).length).toBe(2);
  });

  it("switches list type at the same level", () => {
    const html = parser.parse("- bullet\n1. numbered");
    expect(html).toContain("<ul>");
    expect(html).toContain("</ul>");
    expect(html).toContain("<ol>");
    expect(html).toContain("</ol>");
  });

  it("closes the list after two consecutive blank lines", () => {
    const html = parser.parse("- one\n\n\nAfter list");
    const ulClose = html.indexOf("</ul>");
    const afterIndex = html.indexOf("After list");
    expect(ulClose).toBeGreaterThan(-1);
    expect(afterIndex).toBeGreaterThan(ulClose);
  });

  it("closes the list at the end of the document", () => {
    const html = parser.parse("- only item");
    expect(html.trim().endsWith("</ul>")).toBe(true);
  });

  it("treats an indented continuation line as part of the previous list item", () => {
    const html = parser.parse("- item\n  continued text");
    expect(html).toContain("<br>continued text");
  });

  it("closes the list when a non-indented, non-list line follows", () => {
    const html = parser.parse("- item\nplain paragraph line");
    const ulClose = html.indexOf("</ul>");
    const paragraphIndex = html.indexOf("plain paragraph line");
    expect(ulClose).toBeGreaterThan(-1);
    expect(paragraphIndex).toBeGreaterThan(ulClose);
  });
});
