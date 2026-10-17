// Draw the charts that the server rendered as <canvas data-ai-helper-chart>
// elements inside a health report (see _health_report_chart.html.erb).
// Chart.js comes either from Redmine's global (chart.min, Redmine 6.x) or
// from the importmap's dynamic import (Redmine 7.x). Newly added subtrees
// are drawn too, so charts appear when a report arrives over streaming or
// through an Ajax update.

// Chart.js option builders per payload form. The payload is the JSON stored
// in the canvas' data-ai-helper-chart attribute.
const FORM_CONFIG_BUILDERS = {
  doughnut: buildDoughnutConfig,
  bar: buildBarConfig,
};

/**
 * Build the single dataset shared by every form: per-item colors, border
 * width 1.
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
  };
}

/**
 * Build the Chart.js configuration for a doughnut chart: half-transparent
 * ring with the legend on the right.
 * @param {{title: string, labels: string[]}} payload - The parsed payload.
 * @returns {object} The Chart.js configuration.
 */
function buildDoughnutConfig(payload) {
  return {
    type: "doughnut",
    data: { labels: payload.labels, datasets: [datasetOf(payload)] },
    options: {
      cutout: "50%",
      plugins: {
        title: { display: true, text: payload.title },
        legend: { display: true, position: "right" },
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
  // Mark before drawing so the MutationObserver never re-processes the
  // canvas while a slow loadChart() is still in flight.
  canvas.setAttribute("data-ai-helper-chart-rendered", "");

  const ChartClass = window.Chart;
  if (ChartClass) {
    new ChartClass(canvas, config);
    return;
  }
  loadChart().then(function (loaded) {
    new loaded(canvas, config);
  });
}

/**
 * Draw every not-yet-rendered chart canvas inside the given element.
 * @param {Element|Document} root - The element (or document) to search for
 *   chart canvases.
 * @throws {SyntaxError} When any canvas payload is not valid JSON.
 * @throws {Error} When any canvas payload's form is unsupported.
 */
function renderWithin(root) {
  const canvases = root.querySelectorAll("canvas[data-ai-helper-chart]");
  Array.prototype.forEach.call(canvases, function (canvas) {
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
