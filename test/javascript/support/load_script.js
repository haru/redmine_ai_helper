import { vi } from "vitest";

/**
 * Loads a classic (non-module) script from the repository for its side
 * effects, i.e. the globals it assigns to `window`. Resets the module
 * registry first so the script re-runs from a clean state on every call,
 * even within the same test file.
 *
 * @param {string} relativePathFromRoot e.g. "assets/javascripts/ai_helper_markdown_parser"
 *   (repository-root-relative, without the ".js" extension)
 */
export async function loadScript(relativePathFromRoot) {
  vi.resetModules();
  // @vite-ignore: fully dynamic path, not meant to be statically analyzed/bundled.
  await import(/* @vite-ignore */ `../../../${relativePathFromRoot}.js`);
}
