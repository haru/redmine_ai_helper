# CRF-076: ADR rejected-alternative reason contradicted research R-007, and the wiki claim had no source ID

**Date**: 2026-10-21
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, types, simplify)
**Feature**: branch `081-fix-prompt-template-validation`
**Files**: docs/adr/063-prompt-template-strict-input-variables.md, specs/081-fix-prompt-template-validation/research.md, wiki/pages/issue-summary-instructions-prompt-template.md, wiki/sources.md
**Category**: doc-comment
**Related**: CRF-032, CRF-071

## Feedback

comments review: ADR-063 rejected scanning the body at run time because it "misreads `{...}` inside JSON examples such as the chart directive", but R-007 in the same research file shows the identifier-only pattern does not match `{{ai_helper_chart(...)}}` and the consistency test scans every body with it. The wiki page gained a claim about feature 081 with no source ID, no `sources.md` row and stale frontmatter.

## Original Code

ADR: "...misreads `{...}` inside JSON examples such as the chart directive in the comparison prompt."

## Fix

The reason is limited to loose patterns (`\{[^}]+\}`) and points to the identifier-only pattern used by the test; research R-001 and R-003 were aligned; ADR-063 gained the decisions made in review; the wiki page cites S057 and `sources.md` has the row.

## Root Cause

The ADR copied R-001's alternative faithfully (CRF-032), but R-001 had been written before R-007 and the AI never reconciled the two sections of the same file. The wiki edit was made without reading `wiki/SCHEMA.md`'s citation rule.

## Prevention

Before finalizing an ADR's alternatives, grep research.md for every term in the rejection reason and reconcile contradicting sections. When editing a wiki page, add the source ID, the `sources.md` row and the frontmatter update in the same change.

**Promoted to**: Not yet
