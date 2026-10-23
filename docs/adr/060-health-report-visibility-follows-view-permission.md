# ADR-060: Health report visibility follows the view_ai_helper permission

**Date**: 2026-10-18
**Status**: Accepted

## Context

`AiHelperHealthReport#visible?` allowed only administrators and project members (`user.admin? || user.member_of?(project)`). Generating a report, listing the history (`AiHelperHealthReport.visible`, which checks only that the project is active) and every report action are authorized by `view_ai_helper`. On a public project, Redmine grants that permission to non-members through the built-in Non member role. Such a user could generate a report and see it in the history, but opening, exporting or comparing it returned 403. Since PR #528 (ADR-058), the browser fetches the saved report's content right after generation, so for such a user a successfully generated report was replaced by an error (GitHub Copilot review on PR #528).

## Decision

- `visible?` is `user.admin? || RedmineAiHelper::Util::PermissionChecker.module_enabled?(project:, user:)`, that is `user.allowed_to?(:view_ai_helper, project)`. Anyone who may view the AI Helper on the project may view, export and compare its reports.
- Administrators stay allowed unconditionally, as before (including closed projects, where `allowed_to?` admits only read-only permissions).
- `editable?` keeps `visible? && allowed_to?(:edit_ai_helper_health_reports)`, so editing now also requires `view_ai_helper`. `deletable?` is unchanged.

## Consequences

- Positive: generation, history list, detail, exports and comparison use one rule, so a report a user can generate or see in the list can also be opened.
- Positive: the check reuses the plugin's existing permission helper instead of a hand-written membership test.
- Negative: on public projects whose Non member (or Anonymous) role has `view_ai_helper`, non-members now see every report of the project, not only their own. Administrators who do not want that must withhold `view_ai_helper` from those roles.
- Negative: a member whose role has `edit_ai_helper_health_reports` but not `view_ai_helper` can no longer edit reports (they could not reach the dashboard to see them anyway).

## Alternatives Considered

- **Allow the report's creator in addition to members**: rejected by the user; anyone allowed to view reports should be able to open and export them, not only the person who generated one.
- **Restrict generation to members**: rejected; it would keep the history list showing reports that cannot be opened, and narrows a permission Redmine administrators already grant through roles.
