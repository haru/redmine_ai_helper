// Test double standing in for the chart.js package: Redmine serves the real
// library at runtime (importmap pin on Redmine 7, chart.min on Redmine 6),
// so npm does not install it. The dynamic import in
// assets/javascripts/project_health/ai_helper_health_report_chart.js
// resolves here through vitest's "chart.js" alias (see vitest.config.js).
class StubChart {
  /**
   * Record one chart instantiation so tests can assert on it.
   * @param {HTMLCanvasElement} canvas - The canvas to draw on.
   * @param {object} config - The Chart.js configuration.
   */
  constructor(canvas, config) {
    StubChart.calls.push({ canvas, config });
  }
}
StubChart.calls = [];

export default StubChart;
