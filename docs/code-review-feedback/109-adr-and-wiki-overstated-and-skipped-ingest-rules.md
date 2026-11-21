# CRF-109: ADR-073 and the wiki overstated scope, rewrote research alternatives and skipped ingest rules

**Date**: 2026-11-21
**Source**: Local AI review (speckit-review-run, 6 agents)
**Feature**: branch `bugfix/088-fix-issue-form-rerender`
**Files**: docs/adr/073-issue-form-aids-reattach-on-rerender.md, wiki/pages/issue-ai-features.md, wiki/sources.md, wiki/INDEX.md, specs/088-fix-issue-form-rerender/research.md
**Category**: doc-comment
**Related**: CRF-007, CRF-032, CRF-076, CRF-092

## Feedback

- ADR-073 said a module-disabled project hides the features everywhere, but SF-047 narrowed SC-003 to the global `/issues/new` page.
- Two rejected alternatives were reworded and one reason was invented ("every form keystroke") against research R-002.
- Comments and the ADR named stale line numbers, listed "category" as a trigger on every form, and claimed a collapsed description is absent.
- The wiki section had no S064 source row, no S-number citation, a stale `updated` date, and pushed the page over the 600-word split rule.

## Original Code

"a project with the module disabled renders no hook output, which releases everything ... (SC-003)"

## Fix

The ADR states the `/issues/new` scope and the page-load project elsewhere, restores the research wording for the alternatives, and names the files and versions; the wiki gained S064, citations and a split page (`issue-form-rerender-resilience.md`); research R-004 and tasks T005 record the `@project || issue.project` expression.

## Root Cause

The ADR was summarised from the first spec text instead of re-reading the corrected FR-005/SC-003 and R-002 in the same step, and the wiki ingest steps (sources row, word cap) were skipped.

## Prevention

After a spec correction, re-read every ADR/wiki sentence that restates the corrected requirement. Copy rejected alternatives and reasons from the cited R-NNN verbatim, and run the wiki ingest checklist (source row, citations, 600-word cap) whenever a wiki page is touched.

**Promoted to**: Not yet
