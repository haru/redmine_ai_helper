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
    form: "bar",
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

    it("reports an invalid JSON payload on the canvas instead of throwing", () => {
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
      addCanvas("{not json");

      window.AiHelperHealthReportChart.renderWithin(root);

      const canvas = root.querySelector("canvas");
      expect(canvas.hasAttribute("data-ai-helper-chart-failed")).toBe(true);
      expect(FakeChart.calls.length).toBe(0);
      expect(consoleError).toHaveBeenCalledWith(expect.any(String), expect.any(SyntaxError));
      consoleError.mockRestore();
    });

    it("reports an unsupported form on the canvas instead of throwing", () => {
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
      addCanvas({ ...basePayload, form: "doughnut" });

      window.AiHelperHealthReportChart.renderWithin(root);

      expect(root.querySelector("canvas").hasAttribute("data-ai-helper-chart-failed")).toBe(true);
      expect(FakeChart.calls.length).toBe(0);
      expect(consoleError).toHaveBeenCalledWith(expect.any(String), expect.any(Error));
      consoleError.mockRestore();
    });

    it("shows the container's localized draw-failure message next to a broken canvas", () => {
      vi.spyOn(console, "error").mockImplementation(() => {});
      const wrapper = document.createElement("div");
      wrapper.setAttribute("data-chart-error-message", "描画できませんでした");
      const canvas = document.createElement("canvas");
      canvas.setAttribute("data-ai-helper-chart", "{not json");
      wrapper.appendChild(canvas);
      root.appendChild(wrapper);

      window.AiHelperHealthReportChart.renderWithin(root);

      const warnings = root.querySelectorAll("p.warning");
      expect(warnings.length).toBe(1);
      expect(warnings[0].textContent).toBe("描画できませんでした");
      console.error.mockRestore();
    });

    it("falls back to a generic message when the container has none", () => {
      vi.spyOn(console, "error").mockImplementation(() => {});
      const wrapper = document.createElement("div");
      const canvas = document.createElement("canvas");
      canvas.setAttribute("data-ai-helper-chart", "{not json");
      wrapper.appendChild(canvas);
      root.appendChild(wrapper);

      window.AiHelperHealthReportChart.renderWithin(root);

      const warnings = root.querySelectorAll("p.warning");
      expect(warnings.length).toBe(1);
      expect(warnings[0].textContent).toBe("Failed to draw the chart.");
      console.error.mockRestore();
    });

    it("draws the canvases after a broken one", () => {
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
      addCanvas("{not json");
      const good = addCanvas(basePayload);

      window.AiHelperHealthReportChart.renderWithin(root);

      expect(FakeChart.calls.length).toBe(1);
      expect(FakeChart.calls[0].canvas).toBe(good);
      expect(good.hasAttribute("data-ai-helper-chart-rendered")).toBe(true);
      expect(consoleError).toHaveBeenCalledTimes(1);
      consoleError.mockRestore();
    });

    it("never processes a canvas that already failed", () => {
      vi.spyOn(console, "error").mockImplementation(() => {});
      const wrapper = document.createElement("div");
      const canvas = document.createElement("canvas");
      canvas.setAttribute("data-ai-helper-chart", "{not json");
      wrapper.appendChild(canvas);
      root.appendChild(wrapper);
      window.AiHelperHealthReportChart.renderWithin(root);
      expect(root.querySelectorAll("p.warning").length).toBe(1);

      window.AiHelperHealthReportChart.renderWithin(root);

      expect(root.querySelectorAll("p.warning").length).toBe(1);
      expect(canvas.getAttribute("data-ai-helper-chart-failed")).toBe("");
      console.error.mockRestore();
    });

    it("builds a stacked bar chart with one dataset per item and the legend at the bottom", () => {
      addCanvas({ ...basePayload, form: "stacked" });

      window.AiHelperHealthReportChart.renderWithin(root);

      const config = configOf();
      expect(config.type).toBe("bar");
      expect(config.options.indexAxis).toBe("y");
      expect(config.data.datasets.length).toBe(basePayload.labels.length);
      config.data.datasets.forEach((dataset, index) => {
        expect(dataset.label).toBe(basePayload.labels[index]);
        expect(dataset.data).toEqual([basePayload.values[index]]);
        expect(dataset.backgroundColor).toBe(basePayload.fillColors[index]);
        expect(dataset.borderColor).toBe(basePayload.borderColors[index]);
        expect(dataset.borderWidth).toBe(1);
      });
      expect(config.options.scales.x.stacked).toBe(true);
      expect(config.options.scales.y.stacked).toBe(true);
      expect(config.options.scales.x.ticks.precision).toBe(0);
      expect(config.options.plugins.title.display).toBe(true);
      expect(config.options.plugins.title.text).toBe(basePayload.title);
      expect(config.options.plugins.legend.display).toBe(true);
      expect(config.options.plugins.legend.position).toBe("bottom");
    });

    it("builds a horizontal bar chart with the per-item colors", () => {
      addCanvas(basePayload);

      window.AiHelperHealthReportChart.renderWithin(root);

      const config = configOf();
      expect(config.type).toBe("bar");
      expect(config.data.labels).toEqual(basePayload.labels);
      const dataset = config.data.datasets[0];
      expect(config.data.datasets.length).toBe(1);
      expect(dataset.data).toEqual(basePayload.values);
      expect(dataset.backgroundColor).toEqual(basePayload.fillColors);
      expect(dataset.borderColor).toEqual(basePayload.borderColors);
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

    it("caps the bar thickness so a chart with one item does not draw a huge bar", () => {
      addCanvas({ ...basePayload, labels: [ "New (3)" ], values: [ 3 ] });
      addCanvas({ ...basePayload, form: "stacked", labels: [ "Done (4)" ], values: [ 4 ] });

      window.AiHelperHealthReportChart.renderWithin(root);

      expect(configOf(0).data.datasets[0].maxBarThickness).toBe(48);
      expect(configOf(1).data.datasets[0].maxBarThickness).toBe(48);
    });

    it("sizes the chart container by the number of bars and stops keeping the aspect ratio", () => {
      const labels = [ "A", "B", "C", "D" ];
      const one = addCanvas({ ...basePayload, labels: [ "A" ], values: [ 1 ] });
      const oneParent = document.createElement("div");
      oneParent.appendChild(one);
      root.appendChild(oneParent);
      const four = addCanvas({ ...basePayload, labels: labels, values: [ 1, 2, 3, 4 ] });
      const fourParent = document.createElement("div");
      fourParent.appendChild(four);
      root.appendChild(fourParent);

      window.AiHelperHealthReportChart.renderWithin(root);

      const heightOf = (element) => parseInt(element.style.height, 10);
      expect(heightOf(fourParent) - heightOf(oneParent)).toBe(3 * 36);
      expect(oneParent.style.position).toBe("relative");
      expect(configOf(0).options.maintainAspectRatio).toBe(false);
      expect(configOf(1).options.maintainAspectRatio).toBe(false);
    });

    it("gives a stacked bar chart a fixed container height with its legend", () => {
      const canvas = addCanvas({ ...basePayload, form: "stacked" });
      const parent = document.createElement("div");
      parent.appendChild(canvas);
      root.appendChild(parent);

      window.AiHelperHealthReportChart.renderWithin(root);

      expect(parent.style.height).toBe("170px");
      expect(configOf().options.maintainAspectRatio).toBe(false);
    });

    it("draws every undrawn canvas in the root", () => {
      addCanvas(basePayload);
      addCanvas({ ...basePayload, form: "stacked" });

      window.AiHelperHealthReportChart.renderWithin(root);

      expect(FakeChart.calls.length).toBe(2);
      expect(configOf(1).data.datasets.length).toBe(basePayload.labels.length);
    });
  });

  describe("drawing through the dynamic import (Redmine 7.x)", () => {
    it("marks the canvas before the import resolves and draws it once with the module's class", async () => {
      vi.unstubAllGlobals();
      const StubChart = (await import("chart.js")).default;
      StubChart.calls = [];
      const canvas = addCanvas(basePayload);

      window.AiHelperHealthReportChart.renderWithin(root);
      expect(canvas.hasAttribute("data-ai-helper-chart-rendered")).toBe(true);
      window.AiHelperHealthReportChart.renderWithin(root);
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(StubChart.calls.length).toBe(1);
      expect(StubChart.calls[0].canvas).toBe(canvas);
      expect(StubChart.calls[0].config.type).toBe("bar");
    });

    it("marks the canvas failed, logs the error and shows a warning when Chart.js cannot be loaded", async () => {
      vi.unstubAllGlobals();
      const failure = new Error("chart.js unavailable");
      vi.spyOn(window.AiHelperHealthReportChart, "loadChart").mockRejectedValue(failure);
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
      const wrapper = document.createElement("div");
      const canvas = document.createElement("canvas");
      canvas.setAttribute("data-ai-helper-chart", JSON.stringify(basePayload));
      wrapper.appendChild(canvas);
      root.appendChild(wrapper);

      window.AiHelperHealthReportChart.renderWithin(root);
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(canvas.hasAttribute("data-ai-helper-chart-rendered")).toBe(true);
      expect(canvas.hasAttribute("data-ai-helper-chart-failed")).toBe(true);
      expect(consoleError).toHaveBeenCalledWith(expect.any(String), failure);
      expect(root.querySelectorAll("p.warning").length).toBe(1);
      consoleError.mockRestore();
    });

    it("reports a failure thrown by the Chart constructor of the dynamically loaded module", async () => {
      vi.unstubAllGlobals();
      const failure = new Error("constructor boom");
      const throwingStub = class {
        constructor() {
          throw failure;
        }
      };
      vi.spyOn(window.AiHelperHealthReportChart, "loadChart").mockResolvedValue(throwingStub);
      const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
      const wrapper = document.createElement("div");
      const canvas = document.createElement("canvas");
      canvas.setAttribute("data-ai-helper-chart", JSON.stringify(basePayload));
      wrapper.appendChild(canvas);
      root.appendChild(wrapper);

      window.AiHelperHealthReportChart.renderWithin(root);
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(canvas.hasAttribute("data-ai-helper-chart-failed")).toBe(true);
      expect(consoleError).toHaveBeenCalledWith(expect.any(String), failure);
      expect(root.querySelectorAll("p.warning").length).toBe(1);
      consoleError.mockRestore();
    });
  });

  describe("renderWithin on a canvas itself", () => {
    it("draws the root when the root is an undrawn chart canvas", () => {
      const canvas = addCanvas(basePayload);

      window.AiHelperHealthReportChart.renderWithin(canvas);

      expect(FakeChart.calls.length).toBe(1);
      expect(FakeChart.calls[0].canvas).toBe(canvas);
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
