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
      // down from the measured value for a safe margin. Target: 95.
      // stage 1: ~4.95% (122/2463) -> 4
      // stage 2: ~18.48% (456/2467) -> 18
      // stage 3 (typo_checker): ~35.5% (878/2473) -> 35
      // stage 3 (ai_helper): ~46.51% (1153/2479) -> 46
      // stage 3 (auto_completion): ~46.63% (1156/2479) -> 46
      // stage 4: 92.19% (2290/2484) -> 90
      // stage 5: 96.11% (2972/3092) raised to 95 to match Ruby coverage target
      thresholds: {
        lines: 95,
        perFile: false,
      },
    },
  },
});
