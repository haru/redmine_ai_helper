// Draw the charts that the server rendered as <canvas data-ai-helper-chart>
// elements inside a health report (see _health_report_chart.html.erb).
// Chart.js comes either from Redmine's global (chart.min, Redmine 6.x) or
// from the importmap's dynamic import (Redmine 7.x). Newly added subtrees
// are drawn too, so charts appear when a report arrives over streaming or
// through an Ajax update.

// Chart.js option builders per payload form. The payload is the JSON stored
// in the canvas' data-ai-helper-chart attribute.
// Upper limit (px) of one bar's thickness. Without it a chart with a single
// item stretches its bar over the whole canvas height.
const MAX_BAR_THICKNESS = 48;

// Container height (px) of a horizontal bar chart: room for the title and the
// value axis plus one row per bar, so the height follows the bar count.
const BAR_CHART_BASE_HEIGHT = 80;
const BAR_CHART_ROW_HEIGHT = 36;
// Container height (px) of the single stacked bar: title, bar, axis, legend.
const STACKED_CHART_HEIGHT = 170;

const FORM_CONFIG_BUILDERS = {
  bar: buildBarConfig,
  stacked: buildStackedConfig,
};

/**
 * Build the single dataset of a bar chart: per-item colors, border width 1,
 * capped bar thickness.
 * @param {{values: number[], fillColors: string[], borderColors: string[]}} payload
 *   The parsed chart payload.
 * @returns {object} The Chart.js dataset.
 */
function datasetOf(payload) {
  return {
    data: payload.values,
    backgroundColor: payload.fillColors,
    borderColor: payload.borderColors,
    borderWidth: 1,
    maxBarThickness: MAX_BAR_THICKNESS,
  };
}

/**
 * Build the Chart.js configuration for one stacked horizontal bar: a dataset
 * per item so every segment keeps its own color and legend entry, with the
 * legend at the bottom.
 * @param {{title: string, labels: string[], values: number[], fillColors: string[],
 *   borderColors: string[]}} payload - The parsed payload.
 * @returns {object} The Chart.js configuration.
 */
function buildStackedConfig(payload) {
  return {
    type: "bar",
    data: {
      labels: [""],
      datasets: payload.labels.map(function (label, index) {
        return {
          label: label,
          data: [payload.values[index]],
          backgroundColor: payload.fillColors[index],
          borderColor: payload.borderColors[index],
          borderWidth: 1,
          maxBarThickness: MAX_BAR_THICKNESS,
        };
      }),
    },
    options: {
      indexAxis: "y",
      maintainAspectRatio: false,
      plugins: {
        title: { display: true, text: payload.title },
        legend: { display: true, position: "bottom" },
      },
      scales: {
        x: { stacked: true, ticks: { precision: 0 } },
        y: { stacked: true },
      },
    },
  };
}

/**
 * Build the Chart.js configuration for a horizontal bar chart: integer-only
 * x ticks, no legend.
 * @param {{title: string, labels: string[]}} payload - The parsed payload.
 * @returns {object} The Chart.js configuration.
 */
function buildBarConfig(payload) {
  return {
    type: "bar",
    data: { labels: payload.labels, datasets: [datasetOf(payload)] },
    options: {
      indexAxis: "y",
      maintainAspectRatio: false,
      plugins: {
        title: { display: true, text: payload.title },
        legend: { display: false },
      },
      scales: {
        x: { ticks: { precision: 0 } },
      },
    },
  };
}

/**
 * Give the canvas' container the chart's height. Chart.js fills a dedicated,
 * relatively positioned container when the aspect ratio is not kept.
 * @param {HTMLCanvasElement} canvas - The canvas to size the container of.
 * @param {{form: string, labels: string[]}} payload - The parsed payload.
 */
function sizeContainer(canvas, payload) {
  const container = canvas.parentElement;
  const height = payload.form === "stacked"
    ? STACKED_CHART_HEIGHT
    : BAR_CHART_BASE_HEIGHT + BAR_CHART_ROW_HEIGHT * payload.labels.length;
  container.style.position = "relative";
  container.style.height = `${height}px`;
}

/**
 * Return the Chart.js class to draw with: Redmine's global when present,
 * otherwise the importmap-pinned chart.js module's default export.
 * @returns {Promise<object>} Resolves to the Chart.js class.
 */
function loadChart() {
  if (window.Chart) {
    return Promise.resolve(window.Chart);
  }
  return import("chart.js").then(function (module) {
    return module.default;
  });
}

/**
 * Draw one canvas from its data attribute payload and mark it rendered. The
 * attribute is parsed and the form validated synchronously so a malformed
 * payload surfaces immediately instead of inside a promise.
 * @param {HTMLCanvasElement} canvas - The canvas carrying the payload.
 * @throws {SyntaxError} When the payload is not valid JSON.
 * @throws {Error} When the payload's form is not doughnut or bar.
 */
function drawCanvas(canvas) {
  const payload = JSON.parse(canvas.getAttribute("data-ai-helper-chart"));
  const builder = FORM_CONFIG_BUILDERS[payload.form];
  if (!builder) {
    throw new Error(`Unsupported chart form: ${payload.form}`);
  }
  const config = builder(payload);
  sizeContainer(canvas, payload);
  // Mark before drawing so the MutationObserver never re-processes the
  // canvas while a slow loadChart() is still in flight.
  canvas.setAttribute("data-ai-helper-chart-rendered", "");

  const ChartClass = window.Chart;
  if (ChartClass) {
    new ChartClass(canvas, config);
    return;
  }
  window.AiHelperHealthReportChart.loadChart().then(
    function (loaded) {
      new loaded(canvas, config);
    },
    function (error) {
      // Leave the canvas undrawn-looking so a later insertion can retry, and
      // surface the failure instead of an unexplained blank chart.
      canvas.removeAttribute("data-ai-helper-chart-rendered");
      console.error("Failed to load Chart.js for a health report chart:", error);
    },
  );
}

/**
 * Draw every not-yet-rendered chart canvas inside the given element,
 * including the element itself when it is a chart canvas.
 * @param {Element|Document} root - The element (or document) to search for
 *   chart canvases.
 * @throws {SyntaxError} When any canvas payload is not valid JSON.
 * @throws {Error} When any canvas payload's form is unsupported.
 */
function renderWithin(root) {
  const canvases = Array.prototype.slice.call(root.querySelectorAll("canvas[data-ai-helper-chart]"));
  if (root instanceof Element && root.matches("canvas[data-ai-helper-chart]")) {
    canvases.unshift(root);
  }
  canvases.forEach(function (canvas) {
    if (canvas.hasAttribute("data-ai-helper-chart-rendered")) {
      return;
    }
    drawCanvas(canvas);
  });
}

/**
 * Draw the whole document once loaded and keep drawing every subtree added
 * afterwards (streaming results, Ajax-refreshed panes, previews).
 * @returns {void}
 */
function startChartRendering() {
  renderWithin(document);
  const observer = new MutationObserver(function (mutations) {
    mutations.forEach(function (mutation) {
      Array.prototype.forEach.call(mutation.addedNodes, function (node) {
        if (node.nodeType !== Node.ELEMENT_NODE) {
          return;
        }
        renderWithin(node);
      });
    });
  });
  observer.observe(document.body, { childList: true, subtree: true });
}

document.addEventListener("DOMContentLoaded", startChartRendering);

window.AiHelperHealthReportChart = {
  renderWithin: renderWithin,
  loadChart: loadChart,
};
