# SF-040: Chose a tool name exactly at the 64-character limit with no test guarding it

**Date**: 2026-11-02
**Feature**: specs/084-project-management-tools (branch `feature/084-project-management-tools`)
**Artifact**: plan.md, research.md, data-model.md, contracts/project_tools.md, quickstart.md
**Category**: unconfirmed-assumption
**Related**: None

## Feedback

"Be careful: tool names have a length limit."

## What the AI Wrote

research.md R-001 named the tracker tools in `ProjectWriteTools` `assign_trackers` / `unassign_trackers` and stated:

> All function names fit (the longest is `redmine_ai_helper--tools--project_write_tools--unassign_trackers`, 64 characters).

The generated name was exactly at the 64-character limit. The name format had been taken from `lib/redmine_ai_helper/tools/AGENTS.md` without checking it against a real tool instance, and the plan had no test that fixes the length.

## Correction

- Renamed the functions to `add_trackers` / `remove_trackers` in every artifact; the longest generated name is now 62 characters (`capable_project_props`, `remove_trackers`, `find_member_candidates`).
- Checked the format against a real instance: `VersionWriteTools.tool_classes.first.new.name` returns `redmine_ai_helper--tools--version_write_tools--create_version`.
- Added to research.md R-001 and plan.md that each new tools class test asserts `tool_class.new.name.length <= 64` for all of its `tool_classes`, and that renaming a function updates descriptions, backstories, contracts and tests together.

## Root Cause

The AI read the limit in `tools/AGENTS.md` and computed the lengths, but treated "64 or fewer" as satisfied by a name of exactly 64 characters computed from the documented format. It did not confirm the format against the code (one extra or different separator would push the name over), left no margin, and did not plan a test, so a later rename or a format change would break every request that uses the tool without any test failing.

## Prevention

When a spec or plan names tools: compute each generated name from a real tool instance's `name` (not only from the documented format), keep every name at 62 characters or fewer, list the longest names with their lengths in the plan, and plan a test that asserts `name.length <= 64` for every tool class the feature adds.

**Promoted to**: Not yet
