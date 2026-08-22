import { vi } from "vitest";

/**
 * Several classic scripts wire up their entire behavior inside a single
 * `document.addEventListener('DOMContentLoaded', ...)` call, registering
 * further document-level listeners (click, keydown, ...) from within it.
 * Since `document` is shared across every test in a file, dispatching a
 * real DOMContentLoaded event on it would also re-fire every listener left
 * behind by earlier tests, and the extra listeners registered during setup
 * would keep accumulating on `document` across tests.
 *
 * This loads the given script, captures its DOMContentLoaded listener
 * without registering it on the real document, and invokes it once
 * directly. Any other document-level listeners registered while that
 * handler runs are tracked so the caller can remove them afterwards.
 *
 * @param {string} relativePathFromRoot passed through to loadScript()
 * @returns {Promise<{ removeRegisteredListeners: () => void }>}
 */
export async function loadScriptAndFireDOMContentLoaded(relativePathFromRoot) {
  const { loadScript } = await import("./load_script.js");

  const registered = [];
  const originalAddEventListener = Document.prototype.addEventListener;
  const spy = vi.spyOn(document, "addEventListener").mockImplementation(function (type, listener, options) {
    registered.push([type, listener, options]);
    if (type === "DOMContentLoaded") return undefined;
    return originalAddEventListener.call(document, type, listener, options);
  });

  await loadScript(relativePathFromRoot);

  // Keep the spy active while running the handler(s): production code
  // registers further document-level listeners (click, keydown, ...) from
  // within them, and those must be tracked too, not just the top-level
  // DOMContentLoaded registration itself. A script may register more than
  // one DOMContentLoaded listener, so run all of them, in order.
  const domContentLoadedListeners = registered.filter(([type]) => type === "DOMContentLoaded").map(([, listener]) => listener);
  for (const listener of domContentLoadedListeners) {
    listener();
  }
  spy.mockRestore();
  await new Promise((resolve) => setTimeout(resolve, 0));

  function removeRegisteredListeners() {
    for (const [type, listener, options] of registered) {
      if (type === "DOMContentLoaded") continue;
      document.removeEventListener(type, listener, options);
    }
  }

  return { removeRegisteredListeners };
}
