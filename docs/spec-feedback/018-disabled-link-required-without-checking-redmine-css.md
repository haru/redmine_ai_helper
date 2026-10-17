# SF-018: Required a visibly disabled link in the spec without checking that Redmine has a style for it

**Date**: 2026-10-17
**Feature**: specs/077-fix-dashboard-health-report-error (branch `bugfix/077-fix-dashboard-health-report-error`)
**Artifact**: spec.md (Clarifications, User Story 2, Edge Cases, FR-009, SC-006, Assumptions)
**Category**: unconfirmed-assumption
**Related**: SF-017

## Feedback

During `/speckit-plan`, the AI found that Redmine core has no generic "disabled link" style (only `button.tab-left/right.disabled` and `#context-menu a.disabled`) and asked how the unclickable "Generate report" link should look. The user answered: "I withdraw the requirement to make it unclickable. Do nothing."

## What the AI Wrote

- FR-009: while the edit form is shown in the detail pane, clicking the generate link must not start generation, and "the generate link must look disabled".
- Assumptions: "The disabled generate link gets no tooltip. The disabled state is shown with Redmine's existing look."
- SC-006 and User Story 2 scenarios 3-5 depended on this behaviour.

## Correction

FR-009, SC-006, User Story 2 scenarios 3-5 and the related Edge Cases were removed. The Clarifications entry now says that starting generation with the edit form open removes the form and discards unsaved input (accepted), with no confirmation dialog and no disabled link. The Assumptions bullet now says no CSS changes are made.

## Root Cause

The AI answered a clarification question ("should a confirmation dialog appear?") by inventing a replacement behaviour (a disabled link) and wrote "Redmine's existing look" into the spec without reading Redmine's stylesheets (the disabled selectors it later cited live in `context_menu.css:50` for `#context-menu a.disabled` and `application.css:1900` for `button.tab-left.disabled`; there is no generic disabled-link style). Such a style does not exist, so the requirement could not be met without new CSS. The AI should have checked Redmine's stylesheets before promising a look, and should have asked whether the replacement behaviour was wanted at all.

## Prevention

Before a spec says an element or UI state (table striping, disabled, selected, error, etc.) "looks like Redmine's existing X", grep Redmine's stylesheets for that element or state and name the selector in the spec. If none exists, write it as an open question instead of a requirement. When a clarification answer rejects option A, do not add behaviour B beyond what the user chose without confirming it.

**Promoted to**: AGENTS.md
