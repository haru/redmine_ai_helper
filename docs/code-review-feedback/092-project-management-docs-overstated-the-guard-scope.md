# CRF-092: ADR, wiki, research and comments described the guard, defaults, and Redmine behaviour more broadly or differently than the code

**Date**: 2026-11-03
**Source**: Local AI review (speckit-review-comments)
**Feature**: branch `feature/084-project-management-tools`
**Files**: docs/adr/067-project-management-tools-check-permissions-on-every-object.md, wiki/pages/project-management-tools.md, specs/084-project-management-tools/research.md, lib/redmine_ai_helper/util/project_write_guard.rb, lib/redmine_ai_helper/util/member_hash.rb, lib/redmine_ai_helper/tools/project_tools.rb, assets/prompt_templates/project_agent/backstory.yml
**Category**: doc-comment
**Related**: CRF-005, CRF-007, CRF-032

## Feedback

ADR-067 and the wiki said every tool uses `ProjectWriteGuard` (not `create_project` or `project_members`); the ADR and R-005 said `add_default_member` returns false (it returns the Member and swallows the failure); the wiki omitted the issue_tracking requirement of `list_categories` and that the missing-role refusal is for non-admin creators; the backstory did not say where tracker ids come from; several YARD comments (`project_from_value`, `tracker_hash`, `@param project`, caller lists) were wrong.

## Original Code

```
1. Every tool fetches the target project through `ProjectWriteGuard`
...
- `Project#add_default_member` returns `false` on a validation error
```

## Fix

ADR-067 is append-only, so ADR-068 states the precise scope and corrects the `add_default_member` description; the wiki, research R-005/R-016, comments, tool descriptions, and both backstories were corrected, and a backstory test pins the tracker-id guidance.

## Root Cause

The AI summarised its own design in general words ("every tool") and described Redmine behaviour from memory instead of reading `project.rb` and the callers. AGENTS.md already requires reading the code before documenting what a shared path does.

## Prevention

Before writing "every X does Y" in an ADR, wiki, or comment, grep the callers and list the exceptions; state a Redmine method's return value only after reading its source in the same step.

**Promoted to**: Not yet
