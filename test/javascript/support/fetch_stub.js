import { vi } from "vitest";

/**
 * Replaces global fetch with a vi.fn() so tests never reach the network.
 * @param {(...args: unknown[]) => Promise<Response>} [implementation]
 */
export function stubFetch(implementation) {
  const fetchMock = vi.fn(
    implementation ?? (() => Promise.resolve(new Response(null, { status: 200 })))
  );
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

/**
 * Minimal fake XMLHttpRequest driven by the test via respond()/fail(),
 * so no real network requests are made.
 */
export class FakeXMLHttpRequest {
  constructor() {
    this.status = 0;
    this.statusText = "";
    this.responseText = "";
    this.onload = null;
    this.onerror = null;
  }

  open(method, url) {
    this.method = method;
    this.url = url;
  }

  setRequestHeader(name, value) {
    this.requestHeaders = this.requestHeaders ?? {};
    this.requestHeaders[name] = value;
  }

  send(body) {
    this.body = body;
  }

  respond(status, responseText, statusText) {
    this.status = status;
    this.statusText = statusText ?? "";
    this.responseText = responseText ?? "";
    if (typeof this.onload === "function") this.onload();
  }

  fail() {
    if (typeof this.onerror === "function") this.onerror();
  }
}

/**
 * Replaces global XMLHttpRequest with FakeXMLHttpRequest.
 * @returns {typeof FakeXMLHttpRequest}
 */
export function stubXHR() {
  vi.stubGlobal("XMLHttpRequest", FakeXMLHttpRequest);
  return FakeXMLHttpRequest;
}
