/**
 * Pure layout rules of the chat popup (ADR-064). No DOM and no storage: the
 * viewport size is passed in, so every rule can be tested on its own.
 *
 * A layout is `{left, top, width, height}` in CSS pixels.
 */
const AiHelperChatPopupLayout = (() => {
  const MIN_SIZE = 240;

  /**
   * Limit a value to a range. When the range is empty (high < low) the lower
   * bound wins, so the minimum size is never violated.
   * @param {number} value - The value.
   * @param {number} low - Lower bound.
   * @param {number} high - Upper bound.
   * @returns {number} The limited value.
   */
  function limit(value, low, high) {
    return Math.max(low, Math.min(value, high));
  }

  /**
   * Check that a parsed value has four finite numbers and a positive size.
   * @param {unknown} value - Parsed JSON value read back from localStorage.
   * @returns {boolean} True when the value is a usable layout.
   */
  function isValid(value) {
    if (typeof value !== 'object' || value === null) {
      return false;
    }
    const numbers = [value.left, value.top, value.width, value.height];
    if (!numbers.every((n) => typeof n === 'number' && Number.isFinite(n))) {
      return false;
    }
    return value.width > 0 && value.height > 0;
  }

  /**
   * Fit a layout to the minimum size and the visible viewport. The result is
   * for display only and must not be saved, so a larger window restores the
   * original layout.
   * @param {{left: number, top: number, width: number, height: number}} layout - Layout to fit.
   * @param {{width: number, height: number}} viewport - Visible viewport size.
   * @returns {{left: number, top: number, width: number, height: number}} The fitted layout.
   */
  function clamp(layout, viewport) {
    const width = limit(layout.width, MIN_SIZE, viewport.width);
    const height = limit(layout.height, MIN_SIZE, viewport.height);
    return {
      left: limit(layout.left, 0, Math.max(0, viewport.width - width)),
      top: limit(layout.top, 0, Math.max(0, viewport.height - height)),
      width,
      height,
    };
  }

  /**
   * Compute the layout while a handle is dragged. Only the edges named in
   * `edge` move; the opposite edge stays put at the minimum size, and no edge
   * leaves the viewport (FR-008, FR-009).
   * @param {{left: number, top: number, width: number, height: number}} start - Layout at pointer down.
   * @param {string} edge - One of n, s, e, w, ne, nw, se, sw.
   * @param {{x: number, y: number}} delta - Pointer movement since pointer down.
   * @param {{width: number, height: number}} viewport - Visible viewport size.
   * @returns {{left: number, top: number, width: number, height: number}} The new layout.
   */
  function resized(start, edge, delta, viewport) {
    let { left, top } = start;
    let right = start.left + start.width;
    let bottom = start.top + start.height;
    if (edge.includes('e')) {
      right = limit(right + delta.x, left + MIN_SIZE, viewport.width);
    }
    if (edge.includes('w')) {
      left = limit(left + delta.x, 0, right - MIN_SIZE);
    }
    if (edge.includes('s')) {
      bottom = limit(bottom + delta.y, top + MIN_SIZE, viewport.height);
    }
    if (edge.includes('n')) {
      top = limit(top + delta.y, 0, bottom - MIN_SIZE);
    }
    return { left, top, width: right - left, height: bottom - top };
  }

  /**
   * Compute the layout while the header is dragged: same size, kept inside the viewport.
   * @param {{left: number, top: number, width: number, height: number}} start - Layout at pointer down.
   * @param {{x: number, y: number}} delta - Pointer movement since pointer down.
   * @param {{width: number, height: number}} viewport - Visible viewport size.
   * @returns {{left: number, top: number, width: number, height: number}} The new layout.
   */
  function moved(start, delta, viewport) {
    return clamp({ ...start, left: start.left + delta.x, top: start.top + delta.y }, viewport);
  }

  return { MIN_SIZE, isValid, clamp, resized, moved };
})();

window.AiHelperChatPopupLayout = AiHelperChatPopupLayout;
