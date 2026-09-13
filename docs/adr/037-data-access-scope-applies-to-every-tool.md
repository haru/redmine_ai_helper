# ADR-037: The Data-Access Scope Applies to Every Tool, and Repository Tools Gain Redmine's Own Permission Checks

**Date**: 2026-09-12
**Status**: Accepted (amends the scope of ADR-036)

## Context

ADR-036 made `PermissionChecker.data_accessible?` / `.data_access_condition` the single source of truth for "may AI Helper read/update this project's data for this user", and rolled it out to the eight call sites that had open-coded that decision. Feature 057's clarification S033 deliberately left six tools outside that rollout — `issue_tools.rb`, `wiki_tools.rb`, `board_tools.rb`, `version_tools.rb`, `repository_tools.rb`, `file_tools.rb` — on the stated premise that they "already check only Redmine's standard `visible?`", so adding a gate to them would be YAGNI.

A field report showed the premise does not hold. A user asked AI Helper to summarize an issue belonging to a project where the `ai_helper` module is disabled, with `all_projects_scope` off, and got a summary: `IssueTools#read_issues` checked only `issue.visible?`, which is Redmine's ordinary view-issues permission and says nothing about whether the project opted into AI Helper. The same omission was present in the wiki, board, version and file tools, and in the issue write tools (`create_new_issue`, `update_issue`, reached by `validate_new_issue` / `validate_update_issue`).

Auditing the remaining tools showed the premise was not merely incomplete but wrong for `RepositoryTools`, which performed no check at all — not project visibility, not Redmine's own `:browse_repository` / `:view_changesets`. Every method looked a repository up by ID and returned its branches, tags, file contents and diffs. Because the MCP endpoint exposes `BaseTools` subclasses filtered only by the `admin` and `vector_db_enabled` requirements (`MCP::Server.mcp_tool_allowed?`), this was reachable by any authenticated user, for any repository, including projects they cannot see. Two smaller visibility omissions were found alongside it: `BoardTools#board_info` did not call `board.visible?`, and `IssueTools#capable_issue_properties` did not check project visibility.

## Decision

S033 is withdrawn. Every tool that reaches project-scoped data enforces `PermissionChecker.data_accessible?` (through `BaseTools#accessible_project?`), in addition to — never instead of — Redmine's own visibility and permission checks:

| Tool | Added check |
|---|---|
| `IssueTools#read_issues` | skip issues whose project is not accessible |
| `IssueTools#capable_issue_properties` | raise unless the project is accessible (this also supplies the missing project-visibility check) |
| `IssueUpdateTools#create_new_issue`, `#update_issue` | raise unless the project is accessible, before the existing `:add_issues` / `editable?` check |
| `WikiTools` (all three) | raise unless the wiki's project is accessible |
| `BoardTools` (all five) | raise unless the board's/message's project is accessible; `board_info` also gains the missing `board.visible?` |
| `VersionTools` (both) | raise unless the project is accessible |
| `FileTools#analyze_content_files` | raise unless the resolved container's project is accessible |
| `RepositoryTools` (all five) | raise unless the repository's project is accessible **and** the user holds Redmine's own repository permission |
| `VectorTools#find_similar_issues` | raise unless the **source** issue's project is accessible, before its subject and description are built into the embedding query |
| `IssueSearchTools#search_issues` | AND `data_access_condition` into the query scope unconditionally, not only on the cross-project path |

Two of these rows are about data leaving the instance rather than reaching the caller. `VectorTools#find_similar_issues` previously gated only the *result* issues; the source issue was checked with `visible?` alone, so an issue from a project outside the scope still had its text sent to the embedding provider. And `IssueSearchTools#search_issues` applied the scope only when no `project_id` was given: with one given, `IssueQuery` expands the filter to descendants while `Setting.display_subprojects_issues?` is on (the Redmine default), so subprojects that never opted in were searched. Both are the same rule as the rest of the table — the scope is a property of the data, not of the entry point.

`RepositoryTools` maps Redmine's repository permissions the way Redmine itself maps them (`Redmine::Preparation`): `:browse_repository` for `repository_info`, `get_file_info`, `read_file` and `read_diff` (Redmine's `browse`/`entry`/`raw`/`diff` actions), `:view_changesets` for `get_revision_info` (Redmine's `revision` action). This part is an independent defect fix: it holds regardless of `all_projects_scope`, and would be required even if this plugin had no scope setting of its own.

Write paths are included deliberately. Reading and writing a module-disabled project's data are the same decision — a project whose content must not reach the LLM must equally not be written to by it — so the write tools consult the same predicate rather than a separate rule.

ADR-036's decision table is unchanged. Only the set of call sites that consult it grows. UI gating (`PermissionChecker.module_enabled?`) and the chat-gateway entry check remain out of scope, exactly as ADR-036 left them.

## Consequences

- **Positive**: The data-access scope is now enforced by construction across the whole tool surface rather than on the subset that happened to be audited when ADR-036 was written, and the MCP endpoint inherits this because it calls the same `BaseTools` subclasses.
- **Positive**: The repository tools stop disclosing private projects' source code, branches and diffs to any authenticated user — a defect that predates the scope setting entirely.
- **Negative**: Behavior change for instances that (knowingly or not) relied on AI Helper reaching projects without the module. With `all_projects_scope` off, those tools now refuse; the remedy is to enable the `ai_helper` module on the project or to turn the setting on. This is the intended reading of the setting, but it is still a change to what a working configuration produces.
- **Negative**: `IssueReadAgent#backstory` builds its prompt from `capable_issue_properties`, so constructing an issue agent for a module-disabled project now raises rather than returning properties. In practice the agent is only constructed for a project whose AI Helper UI is reachable, which requires the module; several tests had to enable it explicitly.
- **Negative**: The number of sites consulting the predicate grew from eight to about twenty, so a future change to the decision touches more call sites — mitigated by the fact that they all call one predicate, and none re-implement it.

## Alternatives Considered

- **Keep S033 as written**: rejected — it is the direct cause of the reported behavior, and its stated premise ("these already check Redmine's standard `visible?`") was false for `RepositoryTools` and irrelevant for the rest, since Redmine's `visible?` never encodes the plugin's opt-in.
- **Enforce the check generically in `BaseTools` for every tool call**: rejected — tools take heterogeneous identifiers (`project_id`, `issue_id`, `repository_id`, `board_id`, `message_id`, content type plus ID), so there is no single point before each tool's own lookup at which the project can be derived. ADR-036 rejected a `BaseTools`-only branch for a related reason.
- **Fix the read paths only, leaving `create_new_issue` / `update_issue` as they were**: rejected — writing into a project that is outside the data-access scope is strictly worse than reading from it, and the asymmetry would have to be explained to every future maintainer.
- **Return an empty or filtered result instead of raising**: rejected for single-object lookups — the tools' existing convention is to raise, and an empty result reads to the LLM as "no such data", which it may then assert to the user as fact. `read_issues` still skips rather than raises, because it takes a list and already skips non-visible issues; it raises only when nothing remains.
