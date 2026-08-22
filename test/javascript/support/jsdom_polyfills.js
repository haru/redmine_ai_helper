// jsdom does not implement layout-dependent APIs. Production code that calls
// them (e.g. Element.prototype.scrollIntoView) needs a harmless stub so
// tests can exercise the calling code without errors.
if (typeof Element !== "undefined" && !Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = function () {};
}
