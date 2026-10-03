import { vi } from "vitest";

/**
 * Replaces requestAnimationFrame/cancelAnimationFrame with a manual queue so
 * tests decide when frame callbacks run. Restored by vi.unstubAllGlobals().
 *
 * @returns {{ flush: () => void, pendingCount: () => number }} `flush` runs
 *   every queued callback once; `pendingCount` returns how many are queued.
 */
export function stubAnimationFrames() {
  const callbacks = new Map();
  let nextId = 1;
  vi.stubGlobal("requestAnimationFrame", (callback) => {
    const id = nextId++;
    callbacks.set(id, callback);
    return id;
  });
  vi.stubGlobal("cancelAnimationFrame", (id) => callbacks.delete(id));

  return {
    flush() {
      const queued = Array.from(callbacks.values());
      callbacks.clear();
      queued.forEach((callback) => callback(0));
    },
    pendingCount() {
      return callbacks.size;
    },
  };
}
