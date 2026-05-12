// Tests for AiHelperMarkdownParser issue reference linkification (#NNN -> <a>)
// To run: a JavaScript test environment (e.g., Jest + jsdom) is required.
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
test('linkifies #1234 after whitespace', () => {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('See #1234 please');
  expect(html).toContain('<a href="/issues/1234">#1234</a>');
});

// Case 2: URL reflects relative_url_root subpath
test('uses relative_url_root subpath', () => {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/redmine/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('See #1234');
  expect(html).toContain('<a href="/redmine/issues/1234">#1234</a>');
});

// Case 3: #1234 at start of line is linkified (distinct from H1 heading)
test('linkifies #1234 at start of line when no space follows', () => {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('#1234\nbody');
  expect(html).toMatch(/<a href="\/issues\/1234">#1234<\/a>/);
});

// Case 4: markdown heading syntax ("# Heading") is not linkified
test('does not linkify markdown headings', () => {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('# Heading\nbody');
  expect(html).toContain('<h1>Heading</h1>');
  expect(html).not.toContain('<a href="/issues/');
});

// Case 5: no linkification when preceded by a word character (letter, digit, underscore)
test('does not linkify when preceded by word char', () => {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  expect(parser.parse('abc#1234')).not.toContain('<a href="/issues/');
  expect(parser.parse('v1.0#1234')).not.toContain('<a href="/issues/1234');
  expect(parser.parse('my_var#1234')).not.toContain('<a href="/issues/');
});

// Case 6: no linkification inside fenced code blocks
test('does not linkify inside fenced code blocks', () => {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('```\nSee #1234\n```');
  expect(html).not.toContain('<a href="/issues/1234');
});

// Case 7: no linkification inside inline code
test('does not linkify inside inline code', () => {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('See `#1234` literal');
  expect(html).not.toContain('<a href="/issues/1234');
});

// Case 8: existing markdown links are preserved without double-linking
test('preserves existing markdown links without double-linking', () => {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('Old format: [#1234](/issues/1234)');
  const anchors = html.match(/<a /g) || [];
  expect(anchors.length).toBe(1);
  expect(html).toContain('<a href="/issues/1234">#1234</a>');
});

// Case 9: multiple issue references all get linkified
test('linkifies multiple issue references', () => {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('See #100 and #200 and #100 again');
  expect((html.match(/<a /g) || []).length).toBe(3);
  expect(html).toContain('<a href="/issues/100">#100</a>');
  expect(html).toContain('<a href="/issues/200">#200</a>');
});

// Case 10: no-op when meta tag is absent
test('is a no-op when meta tag is missing', () => {
  removeIssueBaseUrlMeta();
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('See #1234');
  expect(html).not.toContain('<a href=');
});

// Case 11: #1234 inside parentheses is linkified
test('linkifies issue reference inside parentheses', () => {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('(see #1234)');
  expect(html).toContain('<a href="/issues/1234">#1234</a>');
});

// Case 12: XSS defense -- non-digit sequences after # are not linkified
test('does not allow non-digit ID', () => {
  removeIssueBaseUrlMeta();
  setupIssueBaseUrlMeta('/issues/__ID__');
  const parser = new AiHelperMarkdownParser();
  const html = parser.parse('See #abc');
  expect(html).not.toContain('<a href="/issues/');
});
