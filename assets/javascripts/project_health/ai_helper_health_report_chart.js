// Draw the charts that the server rendered as <canvas data-ai-helper-chart>
// elements inside a health report (see _health_report_chart.html.erb).
// Chart.js comes either from Redmine's global (chart.min, Redmine 6.x) or
// from the importmap's dynamic import (Redmine 7.x). Chart directives are
// stripped while a report is still streaming; the canvases first appear in
// the server-rendered body that is swapped in when the generation finishes
// (or that ships with the page on reload), so newly added subtrees are
// drawn too. Charts whose canvases leave the document (another report
// selected, an edit saved, a preview refreshed) are destroyed, since
// Chart.js keeps every instance and its canvas until destroy() is called.

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

// The Chart.js instance drawn on each canvas, so it can be destroyed once
// the canvas has left the document.
const chartInstances = new Map();

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
 * @throws {Error} When the payload's form is not bar or stacked.
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
    chartInstances.set(canvas, new ChartClass(canvas, config));
    return;
  }
  // .then().catch() instead of .then(onFulfilled, onRejected) so a failure
  // inside the fulfilled handler (the Chart constructor) is caught too.
  window.AiHelperHealthReportChart.loadChart().then(function (loaded) {
    // The canvas may have been replaced while Chart.js was loading; a chart
    // drawn on it now would never be destroyed.
    if (!canvas.isConnected) {
      return;
    }
    chartInstances.set(canvas, new loaded(canvas, config));
  }).catch(function (error) {
    // The canvas is marked failed so it is never re-processed, and the
    // failure is shown next to it instead of an unexplained blank box.
    canvas.setAttribute("data-ai-helper-chart-failed", "");
    reportCanvasFailure(canvas, error);
  });
}

/**
 * Report one canvas' drawing failure: log it and show a visible warning
 * next to the chart, so a broken payload or a failed Chart.js load never
 * looks like an ordinary blank chart.
 * @param {HTMLCanvasElement} canvas - The canvas that failed to draw.
 * @param {Error} error - The failure.
 */
function reportCanvasFailure(canvas, error) {
  console.error("Failed to draw a health report chart:", error);
  const container = canvas.parentElement;
  if (!container || !container.parentElement) {
    return;
  }
  const message = container.getAttribute("data-chart-error-message") || "Failed to draw the chart.";
  const warning = document.createElement("p");
  warning.className = "warning";
  warning.textContent = message;
  container.parentElement.insertBefore(warning, container.nextSibling);
}

/**
 * Draw every not-yet-rendered chart canvas inside the given element,
 * including the element itself when it is a chart canvas. A canvas that
 * fails to draw is reported and skipped; the other canvases are still
 * drawn.
 * @param {Element|Document} root - The element (or document) to search for
 *   chart canvases.
 * @returns {void}
 */
function renderWithin(root) {
  const canvases = Array.prototype.slice.call(root.querySelectorAll("canvas[data-ai-helper-chart]"));
  if (root instanceof Element && root.matches("canvas[data-ai-helper-chart]")) {
    canvases.unshift(root);
  }
  canvases.forEach(function (canvas) {
    if (canvas.hasAttribute("data-ai-helper-chart-rendered") || canvas.hasAttribute("data-ai-helper-chart-failed")) {
      return;
    }
    try {
      drawCanvas(canvas);
    } catch (error) {
      canvas.setAttribute("data-ai-helper-chart-failed", "");
      reportCanvasFailure(canvas, error);
    }
  });
}

/**
 * Destroy every chart whose canvas is no longer in the document and forget
 * it. A canvas moved within the document stays connected and keeps its
 * chart.
 * @returns {void}
 */
function releaseDetachedCharts() {
  chartInstances.forEach(function (chart, canvas) {
    if (canvas.isConnected) {
      return;
    }
    chartInstances.delete(canvas);
    chart.destroy();
  });
}

/**
 * Draw the whole document once loaded, keep drawing every subtree added
 * afterwards (swapped-in saved reports, Ajax-refreshed panes, previews) and
 * destroy the charts of removed canvases.
 * @returns {void}
 */
function startChartRendering() {
  renderWithin(document);
  const observer = new MutationObserver(function (mutations) {
    if (mutations.some(function (mutation) { return mutation.removedNodes.length > 0; })) {
      releaseDetachedCharts();
    }
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
