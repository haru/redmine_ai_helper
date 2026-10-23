# CRF-044: Promoted feedback rules were narrowed, half-dropped and mis-cited

**Date**: 2026-10-17
**Source**: Local AI review (spec review: comments agent, `specs/077-fix-dashboard-health-report-error/review.md`)
**Feature**: branch `bugfix/077-fix-dashboard-health-report-error`
**Files**: AGENTS.md, docs/spec-feedback/018-disabled-link-required-without-checking-redmine-css.md
**Category**: doc-comment
**Related**: CRF-032, CRF-037, SF-017, SF-018

## Feedback

- The AGENTS.md rule promoted from SF-017/SF-018 spoke only of a "UI state", dropping SF-017's subject (an element — table striping) from the rule it was supposed to cover.
- SF-018's Prevention has two rules, but only the first was promoted to AGENTS.md; the second ("when a clarification answer rejects option A, do not add behaviour B without confirming it") was lost.
- SF-018's Root Cause said the disabled-link style "does not exist" in Redmine's `application.css`, while the cited selector `#context-menu a.disabled` lives in `context_menu.css:50` — "Redmine's stylesheets" is the accurate scope.

## Fix

The AGENTS.md rule now says "an element or UI state (table striping, a disabled/selected/error state, etc.)" and carries both SF-018 rules in one bullet. SF-018's Root Cause cites the real locations (`context_menu.css:50`, `application.css:1900`) and its Prevention uses "an element or UI state". (Edited in place before merge, as the review explicitly allowed.)

## Root Cause

Promotion was treated as summarising: the AI paraphrased the source entries from memory instead of copying each Prevention sentence and re-checking every file/line citation, so the promoted rule silently narrowed and one of two rules disappeared.

## Prevention

When promoting a feedback entry's Prevention rule into AGENTS.md (or any durable rule file), copy each rule as its own clause, count the rules in the source entry against the clauses in the destination, and re-verify every cited file and line with `grep` in the same step.

**Promoted to**: Not yet
