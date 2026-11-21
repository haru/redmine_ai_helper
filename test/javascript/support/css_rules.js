// Shared CSS source parser for stylesheet contract tests.

/**
 * Collapses whitespace, and drops it around `>` and `,` and inside
 * parentheses, so formatting does not matter when comparing selectors,
 * values and media queries. A descendant combinator (a single space) is kept.
 * @param {string} text a selector, declaration value or media query
 * @returns {string} the normalized text
 */
export function normalize(text) {
  return text.replace(/\s+/g, " ").replace(/\s*([>,])\s*/g, "$1").replace(/\(\s+/g, "(").replace(/\s+\)/g, ")").trim();
}

/**
 * Splits a stylesheet into its innermost rules. @media blocks are entered and
 * @keyframes blocks are skipped. Any construct the scan does not model throws,
 * because the contract tests that use it would silently miss rules (CRF-024,
 * CRF-033). That covers: any other at-rule, a nested @media, a nested rule,
 * unbalanced braces or parentheses, text without a block, a comma inside
 * parentheses in a selector, url() or a missing colon in a declaration, a
 * property declared twice in one rule, and var(--oc-*) inside @keyframes.
 * @param {string} source CSS source, comments allowed
 * @returns {{selectors: string[], declarations: Object<string, string>, media: (string|null)}[]} the rules
 */
export function parseRules(source) {
  const css = source.replace(/\/\*[\s\S]*?\*\//g, "");
  const state = { rules: [], media: [], index: 0 };
  while (!readNext(css, state)) {
    // each step consumes one block boundary
  }
  if (state.media.length !== 0) {
    throw new Error("Unclosed @media block");
  }
  return state.rules;
}

/**
 * Consumes the next block boundary.
 * @param {string} css the stylesheet without comments
 * @param {{rules: object[], media: string[], index: number}} state scan state, updated in place
 * @returns {boolean} true when the end of the stylesheet was reached
 */
function readNext(css, state) {
  const open = css.indexOf("{", state.index);
  const close = css.indexOf("}", state.index);
  if (close !== -1 && (open === -1 || close < open)) {
    if (state.media.length === 0) {
      throw new Error(`Unbalanced closing brace at offset ${close}`);
    }
    state.media.pop();
    state.index = close + 1;
    return false;
  }
  if (open === -1) {
    const rest = css.slice(state.index).trim();
    if (rest !== "") {
      throw new Error(`Trailing text without a block: ${rest.slice(0, 40)}`);
    }
    return true;
  }
  enterBlock(css, state, open);
  return false;
}

/**
 * Handles the block that opens at `open`: @media is entered, @keyframes is
 * skipped, any other at-rule throws, and a style rule is recorded.
 * @param {string} css the stylesheet without comments
 * @param {{rules: object[], media: string[], index: number}} state scan state, updated in place
 * @param {number} open offset of the opening brace
 */
function enterBlock(css, state, open) {
  const prelude = css.slice(state.index, open).trim();
  if (prelude.startsWith("@media")) {
    if (state.media.length > 0) {
      throw new Error(`Nested @media is not modelled: ${prelude}`);
    }
    state.media.push(normalize(prelude.slice(6)));
    state.index = open + 1;
  } else if (prelude.startsWith("@keyframes")) {
    const end = skipBlock(css, open);
    if (/var\(\s*--oc-/i.test(css.slice(open, end))) {
      throw new Error(`var(--oc-*) inside @keyframes is not checked: ${prelude}`);
    }
    state.index = end;
  } else if (prelude.startsWith("@")) {
    throw new Error(`Unsupported at-rule: ${prelude}`);
  } else {
    const end = css.indexOf("}", open);
    const body = css.slice(open + 1, end);
    if (body.includes("{")) {
      throw new Error(`Nested rule inside: ${prelude}`);
    }
    state.rules.push({
      selectors: splitSelectors(prelude),
      declarations: parseDeclarations(body),
      media: state.media.length ? state.media[state.media.length - 1] : null,
    });
    state.index = end + 1;
  }
}

/**
 * Splits a selector list on its top-level commas. A comma inside parentheses
 * (:is(), :has(), :not(), at any depth) is not modelled, so it throws instead
 * of being misread as a list separator.
 * @param {string} prelude the text before the opening brace
 * @returns {string[]} normalized selectors
 */
function splitSelectors(prelude) {
  const parts = [];
  let depth = 0;
  let start = 0;
  Array.from(prelude).forEach((char, i) => {
    depth += { "(": 1, ")": -1 }[char] || 0;
    if (depth < 0) {
      throw new Error(`Unbalanced parentheses in selector: ${prelude}`);
    }
    if (char === ",") {
      if (depth > 0) {
        throw new Error(`Comma inside parentheses in selector: ${prelude}`);
      }
      parts.push(prelude.slice(start, i));
      start = i + 1;
    }
  });
  if (depth !== 0) {
    throw new Error(`Unbalanced parentheses in selector: ${prelude}`);
  }
  parts.push(prelude.slice(start));
  return parts.map(normalize).filter(Boolean);
}

/**
 * Returns the offset just after the block that opens at `open`.
 * @param {string} css the stylesheet
 * @param {number} open offset of the opening brace
 * @returns {number} offset after the matching closing brace
 */
function skipBlock(css, open) {
  let depth = 0;
  for (let i = open; i < css.length; i += 1) {
    depth += { "{": 1, "}": -1 }[css[i]] || 0;
    if (depth === 0) {
      return i + 1;
    }
  }
  throw new Error("Unclosed block");
}

/**
 * Parses a declaration block.
 * @param {string} body text between the braces
 * @returns {Object<string, string>} property to normalized value
 */
function parseDeclarations(body) {
  if (body.includes("url(")) {
    throw new Error("url() in a declaration is not modelled");
  }
  const declarations = {};
  body.split(";").forEach((part) => {
    if (part.trim() === "") {
      return;
    }
    const colon = part.indexOf(":");
    if (colon === -1) {
      throw new Error(`Declaration without a colon: ${part.trim()}`);
    }
    const property = part.slice(0, colon).trim().toLowerCase();
    if (property in declarations) {
      throw new Error(`Property declared twice in one rule: ${property}`);
    }
    declarations[property] = normalize(part.slice(colon + 1));
  });
  return declarations;
}
