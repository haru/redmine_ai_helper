// Recognition rules for {{ai_helper_chart(...)}} directives, kept identical
// to the Ruby Scanner (lib/redmine_ai_helper/health_report_chart/scanner.rb):
// a directive line counts only outside fenced code blocks and outside
// CommonMark HTML blocks of types 1-5, whose content is raw HTML.
// During streaming generation the directive lines are removed from the
// rendered markdown, and a trailing line that is still being received and
// looks like the beginning of a directive is hidden until it is complete.
// See specs/078-health-report-charts/contracts/chart-directive.md.

// A directive occupies a whole line: up to three leading spaces (four would
// be an indented code block), the directive itself, then only spaces/tabs.
const DIRECTIVE_PATTERN = /^[ ]{0,3}\{\{ai_helper_chart\([^()\n]*\)\}\}[ \t]*$/;
// An opening fence line: up to three spaces, then 3+ backticks (whose info
// string must not contain a backtick) or 3+ tildes.
const FENCE_OPEN_BACKTICK_PATTERN = /^[ ]{0,3}(`{3,})[^`]*$/;
const FENCE_OPEN_TILDE_PATTERN = /^[ ]{0,3}(~{3,})/;
// CommonMark HTML block type 1: <script>, <pre>, <style> or <textarea>
// (case-insensitive), followed by whitespace, ">" or the end of the line.
// The block ends only at its own closing tag.
const HTML_BLOCK_TYPE1_PATTERN = /^[ ]{0,3}<(script|pre|style|textarea)(?=[ \t>]|$)/i;
// CommonMark HTML block type 2: an HTML comment.
const HTML_BLOCK_TYPE2_PATTERN = /^[ ]{0,3}<!--/;
// CommonMark HTML block type 3: a processing instruction.
const HTML_BLOCK_TYPE3_PATTERN = /^[ ]{0,3}<\?/;
// CommonMark HTML block type 5: a CDATA section.
const HTML_BLOCK_TYPE5_PATTERN = /^[ ]{0,3}<!\[CDATA\[/;
// CommonMark HTML block type 4: a declaration like <!DOCTYPE html>.
const HTML_BLOCK_TYPE4_PATTERN = /^[ ]{0,3}<![A-Za-z]/;
// The literal every directive starts with, also matched by its non-empty
// prefixes while a line is still arriving.
const DIRECTIVE_PREFIX = "{{ai_helper_chart(";

/**
 * Describe the fence opened by a line, if any.
 * @param {string} line - A single line of the body (no trailing newline).
 * @returns {{char: string, length: number}|null} The fence character and
 *   its run length, or null when the line opens no fence.
 */
function fenceOpenInfo(line) {
  const backtick = line.match(FENCE_OPEN_BACKTICK_PATTERN);
  if (backtick) {
    return { char: "`", length: backtick[1].length };
  }
  const tilde = line.match(FENCE_OPEN_TILDE_PATTERN);
  if (tilde) {
    return { char: "~", length: tilde[1].length };
  }
  return null;
}

/**
 * Tell whether a line closes a fence opened earlier.
 * @param {string} line - A single line of the body (no trailing newline).
 * @param {{char: string, length: number}} fence - The opening fence info.
 * @returns {boolean} True when the line closes the fence.
 */
function fenceCloses(line, fence) {
  const escaped = fence.char.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(`^[ ]{0,3}${escaped}{${fence.length},}[ \\t]*$`);
  return pattern.test(line);
}

/**
 * Tell whether a trailing line still being received must stay hidden: it is
 * either a non-empty prefix of "{{ai_helper_chart(" (a directive still
 * arriving) or starts with it (a directive whose closing ")}}" has not
 * arrived yet; complete directives are removed before this check).
 * @param {string} line - The last line of the body, without its newline.
 * @returns {boolean} True when the line must be hidden.
 */
function hidesPartialDirective(line) {
  const body = line.replace(/^[ ]{0,3}/, "");
  if (body === "") {
    return false;
  }
  return DIRECTIVE_PREFIX.startsWith(body) || body.startsWith(DIRECTIVE_PREFIX);
}

/**
 * Describe the HTML block of type 1-5 opened by a line, if any.
 * @param {string} line - A single line of the body (no trailing newline).
 * @returns {{endPattern: RegExp}|null} The pattern matching the line that
 *   ends the block, or null when the line opens no such block.
 */
function htmlBlockOpenInfo(line) {
  const type1 = line.match(HTML_BLOCK_TYPE1_PATTERN);
  if (type1) {
    return { endPattern: new RegExp(`</${type1[1].toLowerCase()}>`, "i") };
  }
  if (HTML_BLOCK_TYPE2_PATTERN.test(line)) {
    return { endPattern: /-->/ };
  }
  if (HTML_BLOCK_TYPE3_PATTERN.test(line)) {
    return { endPattern: /\?>/ };
  }
  if (HTML_BLOCK_TYPE5_PATTERN.test(line)) {
    return { endPattern: /\]\]>/ };
  }
  if (HTML_BLOCK_TYPE4_PATTERN.test(line)) {
    return { endPattern: />/ };
  }
  return null;
}

/**
 * Describe the block a line opens: a fenced code block, ended by a line of
 * the same character at least as long as the opening, or an HTML block of
 * type 1-5, ended by its end pattern (never at a blank line).
 * @param {string} line - A single line of the body (no trailing newline).
 * @returns {{isHtml: boolean, closes: function(string): boolean}|null} The
 *   open block state, or null when the line opens no block.
 */
function blockOpenInfo(line) {
  const fence = fenceOpenInfo(line);
  if (fence) {
    return { isHtml: false, closes: (candidate) => fenceCloses(candidate, fence) };
  }
  const html = htmlBlockOpenInfo(line);
  if (html) {
    return { isHtml: true, closes: (candidate) => html.endPattern.test(candidate) };
  }
  return null;
}

/**
 * Walk the body line by line and let a callback decide what each line that
 * stands outside fenced code blocks and HTML blocks of type 1-5 becomes.
 * @param {string} markdown - The report body.
 * @param {function(string, boolean): (string|null)} transform - Receives a
 *   line outside those blocks and whether it is the last line; returns the
 *   replacement line, or null to drop it.
 * @returns {string} The rewritten body.
 */
function mapLinesOutsideBlocks(markdown, transform) {
  const lines = String(markdown).split("\n");
  const kept = [];
  let block = null;

  lines.forEach(function (line, index) {
    if (block) {
      if (block.closes(line)) {
        block = null;
      }
      kept.push(line);
      return;
    }
    const opened = blockOpenInfo(line);
    if (opened) {
      // An HTML block's opening line may already carry its end condition,
      // as in "<pre>code</pre>" or "<!-- comment -->". A fence's opening
      // line always matches its own close pattern, so it never closes the
      // fence it opens.
      block = opened.isHtml && opened.closes(line) ? null : opened;
      kept.push(line);
      return;
    }
    const replacement = transform(line, index === lines.length - 1);
    if (replacement !== null) {
      kept.push(replacement);
    }
  });

  return kept.join("\n");
}

/**
 * Remove every chart directive line from the markdown, plus a trailing line
 * that still looks like the beginning of a directive. Text inside fenced
 * code blocks and HTML blocks of type 1-5 is never touched.
 * @param {string} markdown - The report body accumulated so far.
 * @returns {string} The markdown without chart directive lines.
 */
function stripForStreaming(markdown) {
  return mapLinesOutsideBlocks(markdown, function (line, isLastLine) {
    const hidden = DIRECTIVE_PATTERN.test(line) || (isLastLine && hidesPartialDirective(line));
    return hidden ? null : line;
  });
}

/**
 * Replace every chart directive line with a message surrounded by blank
 * lines, for comparison reports where charts cannot be drawn.
 * @param {string} markdown - The comparison analysis text.
 * @param {string} message - The non-empty "cannot draw" text to show.
 * @returns {string} The markdown with directive lines replaced.
 * @throws {TypeError} When message is not a non-empty string.
 */
function replaceForComparison(markdown, message) {
  if (typeof message !== "string" || message === "") {
    throw new TypeError("message must be a non-empty string");
  }
  return mapLinesOutsideBlocks(markdown, function (line) {
    return DIRECTIVE_PATTERN.test(line) ? "\n" + message + "\n" : line;
  });
}

window.AiHelperChartDirective = {
  stripForStreaming: stripForStreaming,
  replaceForComparison: replaceForComparison,
};
