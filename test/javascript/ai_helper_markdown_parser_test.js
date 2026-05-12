// Tests for AiHelperMarkdownParser issue reference linkification (#NNN -> <a>)
// To run these tests, a JavaScript test environment (e.g., Jest + jsdom) is required.
// Without a JS test environment, verify these cases manually.

/**
 * Helper: add <meta name="ai-helper-issue-base-url"> to document.head
 */
function setupIssueBaseUrlMeta(template) {
  const meta = document.createElement('meta');
  meta.name = 'ai-helper-issue-base-url';
  meta.content = template;
  document.head.appendChild(meta);
}

/**
 * Helper: remove all ai-helper-issue-base-url meta tags
 */
function removeIssueBaseUrlMeta() {
  document.head.querySelectorAll('meta[name="ai-helper-issue-base-url"]').forEach(n => n.remove());
}

// Case 1: basic #1234 after whitespace becomes an anchor
function testLinkifiesAfterWhitespace() {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('See #1234 please');
  console.assert(html.includes('<a href="/issues/1234">#1234</a>'),
    'Case 1 FAILED: expected linkified #1234 after whitespace');
  console.log('Case 1 PASSED: linkifies #1234 after whitespace');
}

// Case 2: URL reflects relative_url_root subpath
function testRelativeUrlRootSubpath() {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/redmine/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('See #1234');
  console.assert(html.includes('<a href="/redmine/issues/1234">#1234</a>'),
    'Case 2 FAILED: expected subpath in href');
  console.log('Case 2 PASSED: uses relative_url_root subpath');
}

// Case 3: #1234 at start of line is linkified (distinct from H1 heading)
function testLinkifiesAtLineStart() {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('#1234\nbody');
  console.assert(/<a href="\/issues\/1234">#1234<\/a>/.test(html),
    'Case 3 FAILED: expected linkified #1234 at line start');
  console.log('Case 3 PASSED: linkifies #1234 at start of line');
}

// Case 4: markdown heading syntax ("# Heading") is not linkified
function testNoLinkifyMarkdownHeadings() {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('# Heading\nbody');
  console.assert(html.includes('<h1>Heading</h1>'),
    'Case 4 FAILED: expected <h1> heading');
  console.assert(!html.includes('<a href="/issues/'),
    'Case 4 FAILED: heading should not be linkified');
  console.log('Case 4 PASSED: does not linkify markdown headings');
}

// Case 5: no linkification when preceded by a word character
function testNoLinkifyAfterWordChar() {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  console.assert(!parser.parse('abc#1234').includes('<a href="/issues/'),
    'Case 5a FAILED: abc#1234 should not be linkified');
  console.assert(!parser.parse('v1.0#1234').includes('<a href="/issues/1234'),
    'Case 5b FAILED: v1.0#1234 should not be linkified');
  console.assert(!parser.parse('my_var#1234').includes('<a href="/issues/'),
    'Case 5c FAILED: my_var#1234 should not be linkified');
  console.log('Case 5 PASSED: does not linkify when preceded by word char');
}

// Case 6: no linkification inside fenced code blocks
function testNoLinkifyInCodeBlocks() {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('```\nSee #1234\n```');
  console.assert(!html.includes('<a href="/issues/1234'),
    'Case 6 FAILED: fenced code block should not be linkified');
  console.log('Case 6 PASSED: does not linkify inside fenced code blocks');
}

// Case 7: no linkification inside inline code
function testNoLinkifyInInlineCode() {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('See `#1234` literal');
  console.assert(!html.includes('<a href="/issues/1234'),
    'Case 7 FAILED: inline code should not be linkified');
  console.log('Case 7 PASSED: does not linkify inside inline code');
}

// Case 8: existing markdown links are preserved without double-linking
function testNoDoubleLinking() {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('Old format: [#1234](/issues/1234)');
  const anchors = html.match(/<a /g) || [];
  console.assert(anchors.length === 1,
    `Case 8 FAILED: expected 1 anchor, got ${anchors.length}`);
  console.assert(html.includes('<a href="/issues/1234">#1234</a>'),
    'Case 8 FAILED: expected single link');
  console.log('Case 8 PASSED: preserves existing markdown links without double-linking');
}

// Case 9: multiple issue references all get linkified
function testLinkifiesMultipleReferences() {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('See #100 and #200 and #100 again');
  const count = (html.match(/<a /g) || []).length;
  console.assert(count === 3,
    `Case 9 FAILED: expected 3 anchors, got ${count}`);
  console.assert(html.includes('<a href="/issues/100">#100</a>'),
    'Case 9 FAILED: expected link for #100');
  console.assert(html.includes('<a href="/issues/200">#200</a>'),
    'Case 9 FAILED: expected link for #200');
  console.log('Case 9 PASSED: linkifies multiple issue references');
}

// Case 10: no-op when meta tag is absent
function testNoopWhenMetaAbsent() {
  removeIssueBaseUrlMeta();
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('See #1234');
  console.assert(!html.includes('<a href='),
    'Case 10 FAILED: should be no-op without meta tag');
  console.log('Case 10 PASSED: is a no-op when meta tag is missing');
}

// Case 11: #1234 inside parentheses is linkified
function testLinkifiesInParentheses() {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('(see #1234)');
  console.assert(html.includes('<a href="/issues/1234">#1234</a>'),
    'Case 11 FAILED: expected linkified #1234 in parentheses');
  console.log('Case 11 PASSED: linkifies issue reference inside parentheses');
}

// Case 12: XSS defense -- non-digit sequences after # are not linkified
function testNoLinkifyNonDigitId() {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('See #abc');
  console.assert(!html.includes('<a href="/issues/'),
    'Case 12 FAILED: #abc should not be linkified');
  console.log('Case 12 PASSED: does not allow non-digit ID');
}

// Run all tests
function runAllTests() {
  console.log('=== AiHelperMarkdownParser Issue Linkification Tests ===\n');

  testLinkifiesAfterWhitespace();
  testRelativeUrlRootSubpath();
  testLinkifiesAtLineStart();
  testNoLinkifyMarkdownHeadings();
  testNoLinkifyAfterWordChar();
  testNoLinkifyInCodeBlocks();
  testNoLinkifyInInlineCode();
  testNoDoubleLinking();
  testLinkifiesMultipleReferences();
  testNoopWhenMetaAbsent();
  testLinkifiesInParentheses();
  testNoLinkifyNonDigitId();

  console.log('\n=== All tests completed ===');
}

// Export for module environments, or run directly
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { runAllTests };
} else if (typeof window !== 'undefined') {
  window.runMarkdownParserTests = runAllTests;
}
