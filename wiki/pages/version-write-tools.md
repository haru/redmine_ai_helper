---
title: Version Write Tools
type: component
sources: [S041]
updated: 2026-10-08
---

# Version Write Tools

Feature 068 (GitHub #485) lets AI Helper create, update, and delete Redmine
versions with parity to the Versions REST API (S041). Part of the
[Tool System](./tool-system.md).

## Structure

- **`VersionWriteTools`** (`tools/version_write_tools.rb`) defines
  `create_version` / `update_version` / `delete_version`, all `write: true`.
  It is a separate class from the read-only `VersionTools`, mirroring
  `WikiTools`/`WikiWriteTools` and `IssueTools`/`IssueUpdateTools`; adding to
  `VersionTools` was rejected as it would mix read and write (S041).
- `write: true` alone excludes them in read-only mode in all three places
  (`BaseAgent#available_tool_classes`, MCP `collect_tools`, MCP
  `tool_call_permitted?`), and the MCP server picks up `BaseTools.subclasses`
  automatically — no registration code (S041). See
  [MCP Server Endpoint](./mcp-server-endpoint.md).
- **`VersionTools#capable_version_props(project_id:)`** (read) returns the
  status options, the sharings allowed for a new version in that project, and
  the editable version custom fields (id, name, format, required, options,
  multiple). Without it the AI has no way to learn version custom-field IDs
  (`list_versions`/`version_info` omit them), so SC-006 could not be met (S041).
- `VersionAgent#available_tool_providers` is `[VersionTools, VersionWriteTools]`;
  its en/ja backstory advertises create/update/delete, which is how LeaderAgent
  routes such requests. No separate write agent (WikiAgent holds both as
  precedent), and no custom confirmation flow — LeaderAgent's existing
  "confirm before delete" policy applies (S041).

## Behavior

- **Attributes** are built as a REST-shaped string-key hash and assigned via
  Redmine's `version.safe_attributes=`, then `save`; validation, defaults,
  `default_project_version`, and `Issue.update_versions_from_sharing_change`
  stay Redmine's own (S041). Gotchas: `due_date` aliases `effective_date` and
  `''` clears it; `default_project_version: false` does **not** unset the
  default; deleting a version unsets it via `before_destroy` (S041).
- **Permissions**: create → project found + `accessible_project?` +
  `:manage_versions` on that project. Update/delete → `Version.find_by` +
  `version.visible?` (invisible = same "Version not found" as missing) +
  `accessible_project?` + `:manage_versions` on the **version's own project**,
  not a sharing project (S041).
- **Delete** requires `version.deletable?` (no issues, no custom-field
  reference, no attachments); otherwise an error naming the reason. Then
  `destroy!` (S041).
- **Update semantics**: `nil` = unchanged; `''` clears `due_date`,
  `description`, `wiki_page_title`; `''` for `name`/`status`/`sharing` becomes a
  Redmine validation error; no arguments → no save, current info returned (S041).
- **Custom fields** use `[{field_id, value}]` like issue tools; a nil
  `field_id` is warned and skipped; one value per call (S041).
- One version per call; multi-version requests are repeated calls (S041).

## Decisions

See [Version Write Tools: Strict Input & Error Results](./version-write-tools-error-policy.md).

Related: [Tool System](./tool-system.md) · [Wiki Tools](./wiki-tools.md)
