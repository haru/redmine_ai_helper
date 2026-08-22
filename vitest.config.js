import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "jsdom",
    include: ["test/javascript/**/*.test.js"],
    coverage: {
      provider: "v8",
      include: ["assets/javascripts/**/*.js"],
      exclude: [],
      reporter: ["text", "html", "lcov"],
      reportsDirectory: "coverage-js",
      // Ratchet: initial value is the measured C0 line coverage at the end of
      // stage 1 (~4.95%, 122/2463 lines), rounded down for a safe margin.
      // Raised (never lowered) as later stages add tests. Target: 90 (FR-021).
      thresholds: {
        lines: 4,
        perFile: false,
      },
    },
  },
});
