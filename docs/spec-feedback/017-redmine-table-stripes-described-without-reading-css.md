# SF-017: Described Redmine's table stripes from memory and required equal row colours everywhere

**Date**: 2026-10-16
**Feature**: specs/076-fix-health-report-table-style (branch `bugfix/076-fix-health-report-table-style`)
**Artifact**: spec.md (Background, User Story 1, SC-001, SC-004)
**Category**: unconfirmed-assumption
**Related**: SF-009, SF-016

## Feedback

During `/speckit-plan`, the AI measured the row backgrounds and found that Redmine does not stripe `table.list` inside `.box`. Every health report view is inside `.box`, and chat and summaries are not. The user chose to follow Redmine's rules and not add CSS, and agreed to rewrite the success criteria.

## What the AI Wrote

- Background: "Redmine's standard list table has a grey header row, rows alternate colour, and the hovered row turns yellow."
- User Story 1: "The header row is grey and rows alternate colour."
- SC-004: "In chat history, issue summaries and wiki summaries, the header background and the even-row background are the same as SC-001."

## Correction

- The background now says rows alternate outside `.box` and are all white inside `.box` (Redmine `application.css:724-726`).
- User Story 1 now talks about the grey header and row borders, not stripes.
- SC-001 notes that all five health report views are inside `.box`, so every row is white.
- SC-004 now requires only the header background to match SC-001; row backgrounds follow Redmine's `table.list` rules (striped, since chat and summaries are outside `.box`).

## Root Cause

The AI described Redmine's table style from general knowledge of the issue list, where rows are striped. It did not read the `table.list` rules in Redmine's `application.css` or measure the row colours in the reported view. Even the "coloured" overview section in the user's report has white rows; only the header is grey. Because of that, SC-004 required something Redmine's own CSS contradicts unless the plugin overrides it with its own colours, which AGENTS.md forbids.

## Prevention

When a spec describes how Redmine core styles an element, read the matching rules in Redmine's `app/assets/stylesheets/application.css`, including rules scoped by an ancestor such as `.box`, and cite the lines. A success criterion that compares a style across views must first check, by measurement or by those rules, that the core CSS gives the same value in each view's container.

**Promoted to**: AGENTS.md
