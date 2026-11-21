// Open Color (var(--oc-*)) helpers for stylesheet contract tests.

// CSS function names are ASCII case-insensitive and allow whitespace after the
// opening parenthesis, so every spelling of `var(--oc-` is matched (CRF-033).
const OPEN_COLOR_VAR = /var\(\s*--oc-/i;

/**
 * Finds the next `var(--oc-` at or after `from`.
 * @param {string} source text to search
 * @param {number} from offset to start at
 * @returns {number} the offset, or -1 when there is none
 */
function indexOfOpenColorVar(source, from) {
  const found = source.slice(from).search(OPEN_COLOR_VAR);
  return found === -1 ? -1 : from + found;
}

/**
 * Parses the `var(--oc-NAME[, fallback])` that starts at `start`.
 * @param {string} source text containing the var() call
 * @param {number} start offset of `var(--oc-`
 * @returns {{name: string, fallback: (string|null), start: number, end: number}} the call; `end` is just after the closing parenthesis
 * @throws {Error} on a call this parser does not model
 */
function parseOpenColorVar(source, start) {
  const nameStart = start + OPEN_COLOR_VAR.exec(source.slice(start))[0].length;
  const name = /^[A-Za-z0-9-]+/.exec(source.slice(nameStart));
  if (name === null) {
    throw new Error(`Missing variable name at offset ${start}`);
  }
  const fullName = `--oc-${name[0]}`;
  let cursor = nameStart + name[0].length;
  cursor += /^\s*/.exec(source.slice(cursor))[0].length;
  if (source[cursor] === ")") {
    return { name: fullName, fallback: null, start, end: cursor + 1 };
  }
  if (source[cursor] !== ",") {
    throw new Error(`Expected "," or ")" after ${fullName} at offset ${cursor}`);
  }
  let depth = 1;
  for (let i = cursor + 1; i < source.length; i += 1) {
    depth += { "(": 1, ")": -1 }[source[i]] || 0;
    if (depth === 0) {
      return { name: fullName, fallback: source.slice(cursor + 1, i).trim(), start, end: i + 1 };
    }
  }
  throw new Error(`Unclosed var() at offset ${start}`);
}

/**
 * Rewrites every top-level `var(--oc-*)` call of a value.
 * @param {string} value a declaration value
 * @param {function({name: string, fallback: (string|null)}): string} replace returns the text that takes the place of one call
 * @returns {string} the rewritten value
 */
function mapOpenColorVars(value, replace) {
  let out = "";
  let cursor = 0;
  let index = indexOfOpenColorVar(value, 0);
  while (index !== -1) {
    const parsed = parseOpenColorVar(value, index);
    out += value.slice(cursor, parsed.start) + replace(parsed);
    cursor = parsed.end;
    index = indexOfOpenColorVar(value, cursor);
  }
  return out + value.slice(cursor);
}

/**
 * Tells whether a variable occurrence has a usable (non-empty) fallback.
 * @param {{fallback: (string|null)}} entry an occurrence from findOpenColorVars
 * @returns {boolean} true when the fallback is neither missing nor empty
 */
export function hasFallback(entry) {
  return entry.fallback !== null && entry.fallback !== "";
}

/**
 * Finds every `var(--oc-NAME ...)` in a stylesheet or value, including the ones
 * nested in a fallback. CSS comments are ignored.
 * @param {string} source CSS text
 * @returns {{name: string, fallback: (string|null)}[]} the occurrences, `fallback` is null when there is none
 */
export function findOpenColorVars(source) {
  const css = source.replace(/\/\*[\s\S]*?\*\//g, "");
  const found = [];
  let index = indexOfOpenColorVar(css, 0);
  while (index !== -1) {
    const parsed = parseOpenColorVar(css, index);
    found.push({ name: parsed.name, fallback: parsed.fallback });
    index = indexOfOpenColorVar(css, index + 1);
  }
  return found;
}

/**
 * Resolves a value as Redmine 6 does: every `var(--oc-*, fallback)` becomes
 * its fallback, because Redmine 6 defines no `--oc-*` variable.
 * @param {string} value a declaration value
 * @returns {string} the value with the fallbacks in place
 * @throws {Error} when a `var(--oc-*)`, nested ones included, has no or an empty fallback
 */
export function resolveForRedmine6(value) {
  return mapOpenColorVars(value, (call) => {
    if (!hasFallback(call)) {
      throw new Error(`${call.name} has no fallback in: ${value}`);
    }
    return resolveForRedmine6(call.fallback);
  });
}

/**
 * Resolves a value as Redmine 7 does: the variable is defined, so every
 * fallback is ignored and `var(--oc-NAME, fallback)` is `var(--oc-NAME)`.
 * @param {string} value a declaration value
 * @returns {string} the value with the fallbacks removed
 */
export function resolveForRedmine7(value) {
  return mapOpenColorVars(value, (call) => `var(${call.name})`);
}
