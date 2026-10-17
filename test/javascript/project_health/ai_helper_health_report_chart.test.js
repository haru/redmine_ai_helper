import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScriptAndFireDOMContentLoaded } from "../support/dom_content_loaded.js";
import { loadScript } from "../support/load_script.js";

class FakeChart {
  constructor(canvas, config) {
    FakeChart.calls.push({ canvas, config });
  }
}
FakeChart.calls = [];

describe("AiHelperHealthReportChart", () => {
  let root;
  let cleanup;

  const basePayload = {
    form: "doughnut",
    title: "Issues by Status - 1.0.0",
    labels: [ "New (3)", "Closed (1)" ],
    values: [ 3, 1 ],
    fillColors: [ "rgba(255, 99, 132, 0.2)", "rgba(54, 162, 235, 0.2)" ],
    borderColors: [ "rgb(255, 99, 132)", "rgb(54, 162, 235)" ],
  };

  beforeEach(async () => {
    root = document.createElement("div");
    document.body.appendChild(root);
    FakeChart.calls = [];
    vi.stubGlobal("Chart", FakeChart);
    delete window.AiHelperHealthReportChart;
    await loadScript("assets/javascripts/project_health/ai_helper_health_report_chart");
  });

  afterEach(() => {
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    root.remove();
    vi.unstubAllGlobals();
  });

  function addCanvas(payload, { rendered = false } = {}) {
    const canvas = document.createElement("canvas");
    const value = typeof payload === "string" ? payload : JSON.stringify(payload);
    canvas.setAttribute("data-ai-helper-chart", value);
    if (rendered) {
      canvas.setAttribute("data-ai-helper-chart-rendered", "");
    }
    root.appendChild(canvas);
    return canvas;
  }

  function configOf(index = 0) {
    return FakeChart.calls[index].config;
  }

  describe("renderWithin", () => {
    it("draws an undrawn canvas and marks it rendered", () => {
      const canvas = addCanvas(basePayload);

      window.AiHelperHealthReportChart.renderWithin(root);

      expect(FakeChart.calls.length).toBe(1);
      expect(FakeChart.calls[0].canvas).toBe(canvas);
      expect(canvas.hasAttribute("data-ai-helper-chart-rendered")).toBe(true);
    });

    it("does not redraw an already rendered canvas", () => {
      addCanvas(basePayload, { rendered: true });

      window.AiHelperHealthReportChart.renderWithin(root);

      expect(FakeChart.calls.length).toBe(0);
    });

    it("throws when the data attribute does not hold valid JSON", () => {
      addCanvas("{not json");

      expect(() => window.AiHelperHealthReportChart.renderWithin(root)).toThrow(SyntaxError);
    });

    it("throws when the form is neither doughnut nor bar", () => {
      addCanvas({ ...basePayload, form: "pie" });

      expect(() => window.AiHelperHealthReportChart.renderWithin(root)).toThrow(/form/i);
    });

    it("builds a doughnut chart with the per-item colors and the legend on the right", () => {
      addCanvas(basePayload);

      window.AiHelperHealthReportChart.renderWithin(root);

      const config = configOf();
      expect(config.type).toBe("doughnut");
      expect(config.data.labels).toEqual(basePayload.labels);
      const dataset = config.data.datasets[0];
      expect(config.data.datasets.length).toBe(1);
      expect(dataset.data).toEqual(basePayload.values);
      expect(dataset.backgroundColor).toEqual(basePayload.fillColors);
      expect(dataset.borderColor).toEqual(basePayload.borderColors);
      expect(dataset.borderWidth).toBe(1);
      expect(config.options.cutout).toBe("50%");
      expect(config.options.plugins.title.display).toBe(true);
      expect(config.options.plugins.title.text).toBe(basePayload.title);
      expect(config.options.plugins.legend.display).toBe(true);
      expect(config.options.plugins.legend.position).toBe("right");
    });

    it("builds a horizontal bar chart without a legend and integer ticks", () => {
      addCanvas({ ...basePayload, form: "bar" });

      window.AiHelperHealthReportChart.renderWithin(root);

      const config = configOf();
      expect(config.type).toBe("bar");
      expect(config.data.datasets[0].borderWidth).toBe(1);
      expect(config.options.indexAxis).toBe("y");
      expect(config.options.plugins.title.display).toBe(true);
      expect(config.options.plugins.legend.display).toBe(false);
      expect(config.options.scales.x.ticks.precision).toBe(0);
    });

    it("draws every undrawn canvas in the root", () => {
      addCanvas(basePayload);
      addCanvas({ ...basePayload, form: "bar" });

      window.AiHelperHealthReportChart.renderWithin(root);

      expect(FakeChart.calls.length).toBe(2);
      expect(configOf(1).type).toBe("bar");
    });
  });

  describe("loadChart", () => {
    it("resolves with window.Chart when it is already loaded", async () => {
      expect(await window.AiHelperHealthReportChart.loadChart()).toBe(FakeChart);
    });

    it("falls back to the chart.js module's default export", async () => {
      vi.unstubAllGlobals();
      const fallback = await import("chart.js");

      expect(await window.AiHelperHealthReportChart.loadChart()).toBe(fallback.default);
    });
  });

  describe("startup", () => {
    it("renders the document on DOMContentLoaded and added subtrees afterwards", async () => {
      delete window.AiHelperHealthReportChart;
      const canvas = addCanvas(basePayload);

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_health/ai_helper_health_report_chart");

      expect(FakeChart.calls.length).toBe(1);
      expect(FakeChart.calls[0].canvas).toBe(canvas);

      const laterCanvas = document.createElement("canvas");
      laterCanvas.setAttribute("data-ai-helper-chart", JSON.stringify(basePayload));
      const section = document.createElement("div");
      section.appendChild(laterCanvas);
      root.appendChild(section);
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(FakeChart.calls.length).toBe(2);
      expect(FakeChart.calls[1].canvas).toBe(laterCanvas);
      expect(laterCanvas.hasAttribute("data-ai-helper-chart-rendered")).toBe(true);
    });
  });
});
