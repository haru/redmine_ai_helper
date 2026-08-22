import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { loadScript } from "./support/load_script.js";

// Ported from the pre-existing (never-run) test/javascript/ai_helper_markdown_parser_test.js.
// Each case below preserves the verification intent of the corresponding
// assertion in that file.

describe("AiHelperMarkdownParser issue reference linkification", () => {
  beforeEach(async () => {
    delete window.ai_helper_urls;
    await loadScript("assets/javascripts/ai_helper_markdown_parser");
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
