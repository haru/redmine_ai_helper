import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "jsdom",
    include: ["test/javascript/**/*.test.js"],
    setupFiles: ["./test/javascript/support/jsdom_polyfills.js"],
    coverage: {
      provider: "v8",
      include: ["assets/javascripts/**/*.js"],
      exclude: [],
      reporter: ["text", "html", "lcov"],
      reportsDirectory: "coverage-js",
      // Ratchet: raised (never lowered) as each stage adds tests, rounded
      // down from the measured value for a safe margin. Target: 90 (FR-021).
      // stage 1: ~4.95% (122/2463) -> 4
      // stage 2: ~18.48% (456/2467) -> 18
      thresholds: {
        lines: 18,
        perFile: false,
      },
    },
  },
});
