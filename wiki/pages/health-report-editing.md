---
title: Health Report Editing
type: decision
sources: [S038]
updated: 2026-10-03
---

# Health Report Editing

Users with a dedicated permission can edit a **stored**
[Project Health Report](./health-report.md) in place on the AI Helper tab
(feature 064, issue #475) (S038). How edited reports are rendered and how the
editor UI is wired is covered in
[Health Report Markdown Rendering](./health-report-markdown-rendering.md).

## Keep the original and the latest only

- `ai_helper_health_reports` gains the original body, last editor
  (`last_edited_by_id`), last-edited timestamp (`last_edited_on`), and
  `lock_version` (S038).
- The original is preserved on the **first** edit; there is no edit history —
  only original + latest. Editing via the REST API and a "revert to original"
  action are deliberately not built (YAGNI) (S038).
- "Edited" is decided by `last_edited_on` being present, so the marker survives
  even if the editor record changes (S038).
- Tampering deterrence: an edited marker appears on screen, in the history
  list, and in PDF/Markdown exports, and the original can be toggled into view
  (S038).

## Permission

- New `:edit_ai_helper_health_reports` permission in `project_module
  :ai_helper` (`require: :member`), granted to **no role by default** (S038).
- Model `editable?(user)` = `visible?(user) && user.allowed_to?(...)`; checked
  both by the controller's `authorize` and inside the action. `allowed_to?`
  already handles module enablement, archived/closed projects rejecting write
  actions, and admins (S038).

## Saving

- **Optimistic locking** with Rails' standard `lock_version` — same as Redmine
  issues/wiki and the plugin's `AiHelperProjectSetting`. `StaleObjectError` →
  HTTP 409 with Redmine's `:notice_locking_conflict` text. A hand-rolled
  `updated_at` check was rejected (S038).
- **Gotcha — line endings**: textareas submit `\r\n` while AI-generated bodies
  use `\n`. The submitted body is stripped of `\r` before comparing; if equal,
  nothing is saved and no edited marker/editor/timestamp is set. Without this,
  an unchanged save would look like an edit (S038).
- Because unchanged saves issue no UPDATE, they never hit a lock conflict
  (S038).
- `PATCH .../health_reports/:report_id` returns JSON: `200 {status, html}`
  with the re-rendered detail pane, or `422` (empty body) / `409` (conflict)
  with `errors`; the form is not replaced so input is kept. Reloading the whole
  history list was rejected because it resets pagination and loses the
  selected row (S038).

## Side effects

- **Deleted editor**: `last_edited_by_id` has a foreign key to `users`; a
  `before_destroy` in `RedmineAiHelper::UserPatch` reassigns it to
  `User.anonymous`, mirroring Redmine's `remove_references_before_destroy`.
  A nil-tolerant `|| User.anonymous` at display time was rejected as an
  implicit fallback (S038).
- **Overview cache**: the project overview partial reads `Rails.cache` key
  `"project_health_#{project.id}___"`; the update action deletes it,
  otherwise the pre-edit body shows for up to an hour. Done in the
  controller, not a model callback, because the cache is a view concern
  (S038).
- **Comparison** needs no change: `ProjectAgent#health_report_comparison`
  already reads the current body (S038).

## Exports

- PDF: `project_health_to_pdf` receives `edit_notice:` via its previously
  unused `options` argument and prints it after the header (S038).
- Markdown: new `GET .../health_reports/:report_id/markdown`
  (`health_report_markdown`, under `view_ai_helper`) builds the file from the
  record and prepends a quoted edited notice. The old client-POSTed-body export
  can't attach a trustworthy notice, so it is kept only for unsaved, freshly
  streamed reports (S038).

## Related

[Project Health Report](./health-report.md) ·
[Health Report Markdown Rendering](./health-report-markdown-rendering.md)
