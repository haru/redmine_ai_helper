/**
 * Builds the dashboard detail-pane DOM for a selected report, matching
 * app/views/ai_helper/project/_health_report_body.html.erb:26-29: a
 * `.ai-helper-health-report-body` with NO `.ai-helper-project-health`
 * wrapper; the result area sits inside `.ai-helper-health-report-view`,
 * which sits inside `.ai-helper-project-health-content`. The result area
 * carries the same classes the ERB gives it.
 *
 * @param {HTMLElement} root - Element to attach the pane to.
 * @returns {{detailPane: HTMLElement, contentDiv: HTMLElement, resultDiv: HTMLElement}}
 *   The pane root, its `.ai-helper-project-health-content` ancestor, and
 *   the `#ai-helper-project-health-result` area.
 */
export function createDashboardDetailPane(root) {
  const detailPane = document.createElement("div");
  detailPane.className = "ai-helper-health-report-body";

  const contentDiv = document.createElement("div");
  contentDiv.className = "ai-helper-project-health-content has-report";

  const viewDiv = document.createElement("div");
  viewDiv.className = "ai-helper-health-report-view";

  const resultDiv = document.createElement("div");
  resultDiv.id = "ai-helper-project-health-result";
  resultDiv.className = "ai-helper-health-report-current ai-helper-final-content";
  viewDiv.appendChild(resultDiv);

  contentDiv.appendChild(viewDiv);
  detailPane.appendChild(contentDiv);
  root.appendChild(detailPane);

  return { detailPane, contentDiv, resultDiv };
}
