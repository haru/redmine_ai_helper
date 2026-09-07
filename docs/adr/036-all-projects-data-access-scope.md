# ADR-036: All-Projects Data-Access Scope Decouples Data Access From the ai_helper Module

**Date**: 2026-09-07
**Status**: Accepted

## Context

Every data-reading/updating path in this plugin has, since the plugin's inception, required the `ai_helper` module to be enabled on a project before its data (issues, wiki pages, etc.) is exposed to AI Helper — the "opt-in per project" policy documented in ADR-029 and ADR-030 ("issues from projects without AI Helper enabled must be excluded"). This protects instances where some projects hold information that must not be sent to an LLM.

Some instances have no such requirement — a fully internal deployment, or one using a self-hosted LLM — where the maintainer wants every project to be a data-access target without having to enable the module project-by-project as new projects are created. spec.md captures this as a new instance-wide setting, `all_projects_scope` (default off, preserving the existing behavior exactly).

Introducing this setting means ADR-029's and ADR-030's premise — "AI Helper module enabled" is a necessary condition for data access — is no longer universally true. This ADR records the decision that relaxes it, and why the relaxation is narrower than it might first appear.

## Decision

`RedmineAiHelper::Util::PermissionChecker` gains two class methods, `data_accessible?` (Ruby predicate) and `data_access_condition` (SQL condition for cross-project queries), which become the single source of truth for the "may AI Helper read/update this project's data for this user" decision. Every place that previously open-coded "module enabled + `:view_ai_helper` permission" for this decision (`BaseTools#accessible_project?`/`#accessible_projects`, `IssueSearchTools`'s two cross-project SQL conditions, `VectorTools`'s four result filters and `#collect_permitted_project_ids`, `IssueReadAgent#fetch_todo_issues_from_other_projects`) now delegates to one of these two methods.

The decision table:

| ai_helper module | `all_projects_scope` | `project.visible?(user)` | `user.allowed_to?(:view_ai_helper, project)` | Result |
|---|---|---|---|---|
| enabled | either | false | — | denied |
| enabled | either | true | false | denied |
| enabled | either | true | true | **allowed** |
| disabled | off | either | — | denied |
| disabled | on | false | — | denied |
| disabled | on | true | (not checked) | **allowed** |

When `all_projects_scope` is off, both methods are provably equivalent to the pre-existing logic they replace (`data_accessible?` reduces to `visible? && module_enabled? && allowed_to?(:view_ai_helper)`; `data_access_condition` returns `Project.allowed_to_condition(user, :view_ai_helper)` unchanged) — this is the FR-003 compatibility guarantee, not just a testing convention.

Critically, the relaxation only ever widens the module-**disabled** branch. For a module-enabled project, the decision is unchanged regardless of `all_projects_scope`: the user must still hold `:view_ai_helper`. An administrator who has deliberately withheld `:view_ai_helper` from a role on a module-enabled project (to keep that role away from AI Helper specifically) is not affected by turning `all_projects_scope` on — that exclusion still holds. Only projects that never opted into the module at all become reachable, and only through Redmine's own standard project/data visibility (`visible?`), never through an AI-Helper-specific permission the administrator did not grant.

UI visibility (`PermissionChecker.module_enabled?`, the view hooks, the projects-list icon) and the chat-gateway entry check (`ChatChannel::MessageHandler`, which still gates on `project.module_enabled?(:ai_helper)` for the bound project) are explicitly out of scope for this decision and are not touched — a module-disabled project never shows AI Helper UI or accepts a gateway-bound conversation, even when `all_projects_scope` is on. Only cross-project and other-project **data access** — the thing a user's own chat can already reach today via a module-enabled project — widens.

`AiHelperSetting`'s vector-registration scope (`#vector_scope_projects`, `#vector_target?`) is widened the same way and by the same flag, for the same reason ADR-002's registration scope has always mirrored the data-access scope: a project excluded from data access has no reason to have its content sitting in the vector database.

## Consequences

- **Positive**: The "is this project's data reachable" decision now exists in exactly two methods instead of eight independent call sites, so a future change to the decision (or an audit of it) touches one file.
- **Positive**: Turning `all_projects_scope` on cannot, by construction, grant access beyond what Redmine's own permission system already grants that user — it only removes the plugin's own additional module-enabled gate for the disabled-module case.
- **Positive**: The off-by-default setting means every existing instance's behavior, and every pre-existing automated test that does not explicitly enable it, is provably unchanged (see decision table above).
- **Negative**: The decision table is asymmetric — module-enabled projects keep the `:view_ai_helper` check, module-disabled projects (under the new setting) do not. A future maintainer extending this logic must preserve that asymmetry rather than "simplifying" it to a single condition, or they will silently re-introduce a way to bypass a role's withheld `:view_ai_helper` permission.
- **Negative**: `data_access_condition`'s SQL string is now the second hand-built SQL fragment (after ADR-029/030's) that must be reasoned about for injection safety; it mitigates this by only concatenating Redmine-core-generated SQL and static literals, never user input.

## Alternatives Considered

- **Drop the module-enabled gate entirely when `all_projects_scope` is on** (i.e., `Issue.visible(user)` alone, no `PermissionChecker` involvement): rejected because it would also drop the `:view_ai_helper` check on module-enabled projects, silently undoing an administrator's per-role exclusion from AI Helper — a behavior change the feature's clarifications never asked for and that has no way back short of noticing and re-configuring roles.
- **A per-project override instead of an instance-wide setting**: rejected as an unnecessary interface for the described need (an instance where no project needs the opt-out) and orthogonal to what spec.md's clarifications asked for; a per-project mechanism already exists in the form of the `ai_helper` module itself.
- **Leave the eight call sites independently updated to check the new setting**: rejected under Constitution III (DRY) — the same predicate was already duplicated seven times before this feature; adding an eighth condition to each site would have compounded rather than resolved that duplication, and made the FR-010 (all-routes-consistent) guarantee something that had to be maintained by convention instead of by construction.
