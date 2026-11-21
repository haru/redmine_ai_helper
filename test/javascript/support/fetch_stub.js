import { vi } from "vitest";

/**
 * Let queued promise callbacks and zero-delay timers (including a
 * MutationObserver callback) run.
 * @returns {Promise<void>} resolves after one macrotask
 */
export function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

/**
 * Replace global fetch with a stub that records every call and lets the test
 * settle each call individually.
 *
 * `call.resolve(data)` answers with an ok response: a string `data` is the
 * response text (an HTML body); an object `data` is the JSON body and, when
 * it has an `html` property, that is also the response text.
 * `call.reject(error)` rejects the request.
 *
 * @returns {{calls: Array<{url: string, options: object, resolve: Function, reject: Function}>}} the recorded calls
 */
export function installFetchStub() {
  const calls = [];
  vi.stubGlobal("fetch", function(url, options) {
    const call = { url, options, resolve: null, reject: null };
    call.promise = new Promise((resolve, reject) => {
      call.resolve = (data) => resolve({
        ok: true,
        status: 200,
        json: () => Promise.resolve(data),
        text: () => Promise.resolve(typeof data === "string" ? data : (data.html ?? "")),
      });
      call.reject = reject;
    });
    calls.push(call);
    return call.promise;
  });
  return { calls };
}
