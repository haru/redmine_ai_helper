# CRF-059: Report visibility was narrower than the permission that generates and lists reports

**Date**: 2026-10-18
**Source**: GitHub Copilot (PR #528)
**Feature**: branch `feature/078-health-report-charts` / PR #528 (fix not yet committed)
**Files**: app/models/ai_helper_health_report.rb, test/unit/ai_helper_health_report_test.rb, test/functional/ai_helper_dashboard_controller_test.rb, test/unit/project_health_partial_test.rb, docs/adr/060-health-report-visibility-follows-view-permission.md
**Category**: permission
**Related**: None

## Feedback

A logged-in non-member holding `view_ai_helper` on a public project (through the Non member role) can generate a report, but `visible?` admitted only admins and members. The new post-generation swap fetches `health_report_content`, gets 403 and replaces the successfully generated report with an error (https://github.com/haru/redmine_ai_helper/pull/528#discussion_r4305466614).

## Original Code

```ruby
def visible?(user = User.current)
  return false unless project.present? && user.present?
  user.admin? || user.member_of?(project)
end
```

## Fix

`visible?` is `user.admin? || RedmineAiHelper::Util::PermissionChecker.module_enabled?(project:, user:)` (the user chose "anyone allowed to view reports may export them"; ADR-060). Tests: a non-member with `view_ai_helper` sees the report (unit) and gets 200 from `health_report_content` (functional); both fail with the old `visible?`. Two editable? test setups now grant `view_ai_helper`, since editing requires viewing.

## Root Cause

The feature added a new caller (`health_report_content`, fetched automatically after generation) of an existing check and reused `visible?` as-is, without comparing it with the permission that gates the step before it (`generate_project_health`, authorized by `view_ai_helper`) or with the history scope `AiHelperHealthReport.visible` (project status only). The three checks had diverged before this PR, but only the new automatic chain "generate, then fetch" made a user hit both ends of it. The plugin already had `PermissionChecker.module_enabled?` for exactly this decision.

## Prevention

When a flow chains two actions automatically (generate, then fetch/export the result), list the authorization check of each step and confirm a user who passes the first passes the second; add a test with a user who has the first step's permission but no other privilege (non-member, non-admin). Decide "can view AI Helper data" with `PermissionChecker`, not with a hand-written membership test.

**Promoted to**: Not yet
