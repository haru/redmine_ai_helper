import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadScriptAndFireDOMContentLoaded } from "../support/dom_content_loaded.js";
import { loadScript } from "../support/load_script.js";

function createXhrMock() {
  const instances = [];
  vi.stubGlobal(
    "XMLHttpRequest",
    class {
      constructor() {
        this.open = vi.fn();
        this.send = vi.fn();
        this.setRequestHeader = vi.fn();
        this.responseText = "";
        this.status = 200;
        this.onload = null;
        this.onerror = null;
        instances.push(this);
      }
    },
  );
  return instances;
}

describe("AiHelperMasterDetail", () => {
  let container;
  let cleanup;

  beforeEach(() => {
    container = document.createElement("div");
    document.body.appendChild(container);
    delete window.AiHelperMasterDetail;
    delete window.updateHealthReportHistory;
    delete window.updateComparisonButton;
    delete window.AiHelperMarkdownParser;
  });

  afterEach(() => {
    cleanup?.removeRegisteredListeners();
    cleanup = undefined;
    container.remove();
    document.querySelectorAll('meta[name^="i18n-"], meta[name="csrf-token"]').forEach((m) => m.remove());
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  function addMeta(name, content) {
    const meta = document.createElement("meta");
    meta.setAttribute("name", name);
    meta.setAttribute("content", content);
    document.head.appendChild(meta);
    return meta;
  }

  function addLayout() {
    const layout = document.createElement("div");
    layout.className = "ai-helper-master-detail-layout";

    const masterPane = document.createElement("div");
    masterPane.className = "ai-helper-master-pane";

    const detailPane = document.createElement("div");
    detailPane.className = "ai-helper-detail-pane";

    const detailContainer = document.createElement("div");
    detailContainer.id = "ai-helper-health-report-detail-container";

    layout.append(masterPane, detailPane, detailContainer);
    container.appendChild(layout);

    return { layout, masterPane, detailPane, detailContainer };
  }

  function addReportRow({
    reportId = "1",
    reportContent = "# Hello",
    createdAt = "2026-01-01T00:00:00Z",
    userName = "Alice",
    selected = false,
    parent,
  } = {}) {
    const row = document.createElement("tr");
    row.className = "ai-helper-report-row" + (selected ? " selected" : "");
    row.dataset.reportId = reportId;
    row.dataset.reportContent = reportContent;
    row.dataset.reportCreatedAt = createdAt;
    row.dataset.reportUserName = userName;

    const cell = document.createElement("td");
    cell.className = "ai-helper-clickable-cell";
    row.appendChild(cell);

    const deleteLink = document.createElement("a");
    deleteLink.className = "icon-del";
    deleteLink.href = `/health_reports/${reportId}`;
    deleteLink.dataset.confirm = "Really?";
    row.appendChild(deleteLink);

    (parent || container).appendChild(row);
    return { row, cell, deleteLink };
  }

  async function loadClass() {
    await loadScript("assets/javascripts/project_health/ai_helper_master_detail");
    return window.AiHelperMasterDetail;
  }

  describe("initialization", () => {
    it("does nothing when the master-detail layout is absent", async () => {
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();

      expect(instance.masterPane).toBeNull();
      expect(instance.detailPane).toBeNull();
      expect(instance.detailContainer).toBeNull();
    });

    it("wires up panes and existing selection when the layout is present", async () => {
      const { masterPane, detailPane, detailContainer } = addLayout();
      addReportRow({ reportId: "5", selected: true });
      const AiHelperMasterDetail = await loadClass();

      const instance = new AiHelperMasterDetail();

      expect(instance.masterPane).toBe(masterPane);
      expect(instance.detailPane).toBe(detailPane);
      expect(instance.detailContainer).toBe(detailContainer);
      expect(instance.selectedReportId).toBe("5");
    });
  });

  describe("selectReport via clickable cell", () => {
    it("selects the row, marks it selected, and renders the detail after clicking", async () => {
      vi.useFakeTimers();
      addLayout();
      const { row, cell } = addReportRow({ reportId: "3", reportContent: "**bold**", userName: "Bob" });
      const AiHelperMasterDetail = await loadClass();
      new AiHelperMasterDetail();

      cell.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(row.classList.contains("selected")).toBe(true);

      const detailContainer = document.getElementById("ai-helper-health-report-detail-container");
      expect(detailContainer.style.opacity).toBe("0");

      await vi.advanceTimersByTimeAsync(300);

      expect(detailContainer.innerHTML).toContain("data-report-id=\"3\"");
      expect(detailContainer.innerHTML).toContain("Bob");

      await vi.advanceTimersByTimeAsync(10);
      expect(detailContainer.style.opacity).toBe("1");
    });

    it("does nothing when clicking the already-selected report", async () => {
      vi.useFakeTimers();
      addLayout();
      const { cell } = addReportRow({ reportId: "3", selected: true });
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();
      const updateSpy = vi.spyOn(instance, "updateSelection");

      cell.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(updateSpy).not.toHaveBeenCalled();
    });

    it("uses the markdown parser to format content when it is available", async () => {
      vi.useFakeTimers();
      await loadScript("assets/javascripts/shared/ai_helper_markdown_parser");
      addLayout();
      const { cell } = addReportRow({ reportId: "9", reportContent: "**strong**" });
      const AiHelperMasterDetail = await loadClass();
      new AiHelperMasterDetail();

      cell.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      await vi.advanceTimersByTimeAsync(300);

      const detailContainer = document.getElementById("ai-helper-health-report-detail-container");
      expect(detailContainer.innerHTML).toContain("<strong>strong</strong>");
    });

    it("switches selection between rows, clearing the previous one", async () => {
      vi.useFakeTimers();
      addLayout();
      const { row: row1, cell: cell1 } = addReportRow({ reportId: "1" });
      const { row: row2, cell: cell2 } = addReportRow({ reportId: "2" });
      const AiHelperMasterDetail = await loadClass();
      new AiHelperMasterDetail();

      cell1.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      cell2.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(row1.classList.contains("selected")).toBe(false);
      expect(row2.classList.contains("selected")).toBe(true);
    });
  });

  describe("buildDetailHTML", () => {
    it("escapes user-controlled fields and uses i18n meta tags when present", async () => {
      addMeta("i18n-label_export_to", "Exporter vers");
      addMeta("i18n-field_created_on", "Créé le");
      addMeta("i18n-field_author", "Auteur");
      addLayout();
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();

      const html = instance.buildDetailHTML(
        {
          id: "7",
          created_at: "2026-01-01T00:00:00Z",
          user: { name: "<script>alert(1)</script>" },
          health_report: "raw content",
        },
        "<p>formatted</p>",
      );

      expect(html).toContain("Exporter vers");
      expect(html).toContain("Créé le");
      expect(html).toContain("Auteur");
      expect(html).not.toContain("<script>alert(1)</script>");
      expect(html).toContain("&lt;script&gt;");
      expect(html).toContain("<p>formatted</p>");
    });

    it("falls back to default English labels when no i18n meta tags are present", async () => {
      addLayout();
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();

      const html = instance.buildDetailHTML(
        { id: "1", created_at: "2026-01-01T00:00:00Z", user: { name: "Carol" }, health_report: "x" },
        "content",
      );

      expect(html).toContain("Export to");
      expect(html).toContain("Created on");
      expect(html).toContain("Author");
    });
  });

  describe("showLoading / showError", () => {
    it("renders a loader and an escaped error message", async () => {
      addLayout();
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();

      instance.showLoading();
      expect(instance.detailContainer.innerHTML).toContain("ai-helper-loader");

      instance.showError("<b>boom</b>");
      expect(instance.detailContainer.innerHTML).toContain("&lt;b&gt;boom&lt;/b&gt;");
    });
  });

  describe("loadReportDetail", () => {
    it("renders the detail on a successful JSON response", async () => {
      addLayout();
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();
      const xhrInstances = createXhrMock();
      const renderSpy = vi.spyOn(instance, "renderReportDetail");

      instance.loadReportDetail("/reports/1");
      const xhr = xhrInstances[0];
      xhr.status = 200;
      xhr.responseText = JSON.stringify({ id: "1", user: { name: "Dan" } });
      xhr.onload();

      expect(renderSpy).toHaveBeenCalledWith({ id: "1", user: { name: "Dan" } });
    });

    it("shows an error when the response is not valid JSON", async () => {
      addLayout();
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();
      const xhrInstances = createXhrMock();

      instance.loadReportDetail("/reports/1");
      const xhr = xhrInstances[0];
      xhr.status = 200;
      xhr.responseText = "not json";
      xhr.onload();

      expect(instance.detailContainer.innerHTML).toContain("Failed to load report");
    });

    it("shows an error with the HTTP status when the request fails", async () => {
      addLayout();
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();
      const xhrInstances = createXhrMock();

      instance.loadReportDetail("/reports/1");
      const xhr = xhrInstances[0];
      xhr.status = 500;
      xhr.responseText = "";
      xhr.onload();

      expect(instance.detailContainer.innerHTML).toContain("Status: 500");
    });

    it("shows a network error message on xhr.onerror", async () => {
      addLayout();
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();
      const xhrInstances = createXhrMock();

      instance.loadReportDetail("/reports/1");
      xhrInstances[0].onerror();

      expect(instance.detailContainer.innerHTML).toContain("Network error occurred");
    });
  });

  describe("handleDelete", () => {
    it("does nothing when the confirmation dialog is dismissed", async () => {
      addLayout();
      const { deleteLink } = addReportRow({ reportId: "4" });
      const AiHelperMasterDetail = await loadClass();
      new AiHelperMasterDetail();
      const xhrInstances = createXhrMock();
      vi.stubGlobal("confirm", vi.fn(() => false));

      deleteLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      expect(xhrInstances.length).toBe(0);
    });

    it("sends a DELETE request with the CSRF token and removes the row on success", async () => {
      addMeta("csrf-token", "tok-123");
      addLayout();
      const { row, deleteLink } = addReportRow({ reportId: "4", selected: true });
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();
      const xhrInstances = createXhrMock();
      vi.stubGlobal("confirm", vi.fn(() => true));
      const selectNextSpy = vi.spyOn(instance, "selectNextReport").mockImplementation(() => {});

      deleteLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

      const xhr = xhrInstances[0];
      expect(xhr.open.mock.calls[0][0]).toBe("DELETE");
      expect(xhr.open.mock.calls[0][1]).toContain("/health_reports/4");
      expect(xhr.open.mock.calls[0][2]).toBe(true);
      expect(xhr.setRequestHeader).toHaveBeenCalledWith("X-CSRF-Token", "tok-123");

      xhr.status = 200;
      xhr.onload();

      expect(row.isConnected).toBe(false);
      expect(selectNextSpy).toHaveBeenCalled();
    });

    it("does not call selectNextReport when the deleted row was not selected", async () => {
      addLayout();
      const { deleteLink } = addReportRow({ reportId: "4", selected: false });
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();
      instance.selectedReportId = "other";
      const xhrInstances = createXhrMock();
      vi.stubGlobal("confirm", vi.fn(() => true));
      const selectNextSpy = vi.spyOn(instance, "selectNextReport").mockImplementation(() => {});

      deleteLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      xhrInstances[0].status = 200;
      xhrInstances[0].onload();

      expect(selectNextSpy).not.toHaveBeenCalled();
    });

    it("alerts on a failed delete response", async () => {
      addLayout();
      const { deleteLink } = addReportRow({ reportId: "4" });
      const AiHelperMasterDetail = await loadClass();
      new AiHelperMasterDetail();
      const xhrInstances = createXhrMock();
      vi.stubGlobal("confirm", vi.fn(() => true));
      const alertSpy = vi.fn();
      vi.stubGlobal("alert", alertSpy);

      deleteLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      xhrInstances[0].status = 500;
      xhrInstances[0].onload();

      expect(alertSpy).toHaveBeenCalledWith("Failed to delete report");
    });

    it("alerts on a network error during delete", async () => {
      addLayout();
      const { deleteLink } = addReportRow({ reportId: "4" });
      const AiHelperMasterDetail = await loadClass();
      new AiHelperMasterDetail();
      const xhrInstances = createXhrMock();
      vi.stubGlobal("confirm", vi.fn(() => true));
      const alertSpy = vi.fn();
      vi.stubGlobal("alert", alertSpy);

      deleteLink.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      xhrInstances[0].onerror();

      expect(alertSpy).toHaveBeenCalledWith("Network error occurred");
    });
  });

  describe("selectNextReport", () => {
    it("selects the first remaining report when others exist", async () => {
      addLayout();
      addReportRow({ reportId: "1" });
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();
      const selectSpy = vi.spyOn(instance, "selectReport").mockImplementation(() => {});

      instance.selectNextReport();

      expect(selectSpy).toHaveBeenCalled();
    });

    it("shows the placeholder when no reports remain", async () => {
      addLayout();
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();

      instance.selectNextReport();

      expect(instance.detailContainer.innerHTML).toContain("ai-helper-detail-placeholder");
      expect(instance.selectedReportId).toBeNull();
    });
  });

  describe("exportMarkdown", () => {
    it("submits a form with the report content and CSRF token to the project-scoped export URL", async () => {
      addMeta("csrf-token", "tok-xyz");
      Object.defineProperty(window, "location", {
        value: new URL("http://localhost/projects/42/ai_helper/health_reports"),
        writable: true,
      });
      addLayout();
      const detailContainer = document.getElementById("ai-helper-health-report-detail-container");
      detailContainer.innerHTML = '<a href="#" id="ai-helper-markdown-export-detail">Markdown</a>';
      const AiHelperMasterDetail = await loadClass();
      const instance = new AiHelperMasterDetail();
      instance.attachExportEvents({ health_report: "raw md" });

      const submitSpy = vi.spyOn(HTMLFormElement.prototype, "submit").mockImplementation(() => {});
      const appendChildSpy = vi.spyOn(document.body, "appendChild");

      document.getElementById("ai-helper-markdown-export-detail").dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );

      const form = appendChildSpy.mock.calls.find(([node]) => node.tagName === "FORM")?.[0];
      expect(form.action).toContain("/projects/42/ai_helper/project_health_markdown");
      expect(form.querySelector('input[name="health_report_content"]').value).toBe("raw md");
      expect(form.querySelector('input[name="authenticity_token"]').value).toBe("tok-xyz");
      expect(submitSpy).toHaveBeenCalledTimes(1);

      submitSpy.mockRestore();
      appendChildSpy.mockRestore();
    });
  });

  describe("window.updateHealthReportHistory", () => {
    it("does nothing when the history container is absent", async () => {
      addLayout();
      await loadClass();
      const xhrInstances = createXhrMock();

      window.updateHealthReportHistory();

      expect(xhrInstances.length).toBe(0);
    });

    it("reloads the history, re-initializes, and auto-selects the first report without a callback", async () => {
      vi.useFakeTimers();
      Object.defineProperty(window, "location", {
        value: new URL("http://localhost/projects/8/ai_helper/health_reports"),
        writable: true,
      });
      const historyContainer = document.createElement("div");
      historyContainer.id = "ai-helper-health-report-history-container";
      container.appendChild(historyContainer);
      addLayout();
      await loadClass();
      const xhrInstances = createXhrMock();

      window.updateHealthReportHistory();

      const xhr = xhrInstances[0];
      expect(xhr.open).toHaveBeenCalledWith("GET", "/projects/8/ai_helper/health_reports", true);

      xhr.status = 200;
      xhr.responseText =
        '<table><tr class="ai-helper-report-row" data-report-id="1" data-report-content="c" ' +
        'data-report-created-at="2026-01-01" data-report-user-name="Eve">' +
        '<td class="ai-helper-clickable-cell"></td></tr></table>';
      xhr.onload();

      expect(historyContainer.innerHTML).toContain("ai-helper-report-row");

      await vi.advanceTimersByTimeAsync(100);

      const row = historyContainer.querySelector(".ai-helper-report-row");
      expect(row.classList.contains("selected")).toBe(true);
    });

    it("invokes the provided callback instead of auto-selecting", async () => {
      const historyContainer = document.createElement("div");
      historyContainer.id = "ai-helper-health-report-history-container";
      container.appendChild(historyContainer);
      addLayout();
      await loadClass();
      const xhrInstances = createXhrMock();
      const callback = vi.fn();

      window.updateHealthReportHistory(callback);
      const xhr = xhrInstances[0];
      xhr.status = 200;
      xhr.responseText = "<table></table>";
      xhr.onload();

      expect(callback).toHaveBeenCalledWith(expect.any(window.AiHelperMasterDetail));
    });

    it("does not touch the container when the request fails", async () => {
      const historyContainer = document.createElement("div");
      historyContainer.id = "ai-helper-health-report-history-container";
      historyContainer.innerHTML = "<p>original</p>";
      container.appendChild(historyContainer);
      addLayout();
      await loadClass();
      const xhrInstances = createXhrMock();

      window.updateHealthReportHistory();
      const xhr = xhrInstances[0];
      xhr.status = 500;
      xhr.onload();

      expect(historyContainer.innerHTML).toBe("<p>original</p>");
    });
  });

  describe("window.updateComparisonButton", () => {
    function addCompareUi() {
      const oldRadio = document.createElement("input");
      oldRadio.type = "radio";
      oldRadio.className = "old-radio";
      oldRadio.value = "1";

      const newRadio = document.createElement("input");
      newRadio.type = "radio";
      newRadio.className = "new-radio";
      newRadio.value = "2";

      const button = document.createElement("button");
      button.id = "compare-reports-button";

      container.append(oldRadio, newRadio, button);
      return { oldRadio, newRadio, button };
    }

    it("does nothing when the compare button is absent", async () => {
      await loadClass();
      expect(() => window.updateComparisonButton()).not.toThrow();
    });

    it("enables the button when two different reports are checked", async () => {
      const { oldRadio, newRadio, button } = addCompareUi();
      oldRadio.checked = true;
      newRadio.checked = true;
      await loadClass();

      window.updateComparisonButton();

      expect(button.disabled).toBe(false);
    });

    it("disables the button when the same report is checked on both sides", async () => {
      const { oldRadio, newRadio, button } = addCompareUi();
      oldRadio.value = "1";
      newRadio.value = "1";
      oldRadio.checked = true;
      newRadio.checked = true;
      await loadClass();

      window.updateComparisonButton();

      expect(button.disabled).toBe(true);
    });

    it("disables the button when only one side is checked", async () => {
      const { oldRadio, button } = addCompareUi();
      oldRadio.checked = true;
      await loadClass();

      window.updateComparisonButton();

      expect(button.disabled).toBe(true);
    });
  });

  describe("auto-init on DOMContentLoaded", () => {
    it("instantiates AiHelperMasterDetail and initializes the comparison button", async () => {
      const { button } = (() => {
        const b = document.createElement("button");
        b.id = "compare-reports-button";
        container.appendChild(b);
        return { button: b };
      })();
      addLayout();
      addReportRow({ reportId: "1", selected: true });

      cleanup = await loadScriptAndFireDOMContentLoaded("assets/javascripts/project_health/ai_helper_master_detail");

      expect(button.disabled).toBe(true);
    });
  });
});
