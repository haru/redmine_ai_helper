# CRF-060: The JS directive scanner missed the HTML-block fix made to the Ruby scanner

**Date**: 2026-10-18
**Source**: GitHub Copilot (PR #528)
**Feature**: branch `feature/078-health-report-charts` / PR #528 (fix not yet committed)
**Files**: assets/javascripts/project_health/ai_helper_chart_directive.js, test/javascript/project_health/ai_helper_chart_directive.test.js, test/unit/lib/health_report_chart/scanner_test.rb
**Category**: convention-violation
**Related**: CRF-051, CRF-053

## Feedback

`mapLinesOutsideFences` tracked fences only, while the Ruby Scanner keeps CommonMark HTML blocks of types 1-5. A directive inside `<pre>` was removed while streaming or replaced in comparisons instead of kept; a backtick fence line inside an HTML comment left the walker in fence state after `-->`, hiding later real directives (https://github.com/haru/redmine_ai_helper/pull/528#discussion_r4305466638).

## Original Code

```js
const opened = fenceOpenInfo(line);
if (opened) {
  fence = opened;
```

## Fix

The JS walker ports Ruby's HTML block opening and end rules (types 1-5, opening line may self-close, fences and HTML blocks never open inside each other). Block state carries its own `closes(line)` so no unreachable kind switch is needed. The Ruby test cases for HTML blocks were copied into the JS tests (17 cases, plus one for `replaceForComparison`); the comment-containing-a-fence case was added to both languages. `contracts/chart-directive.md` now documents the HTML block rules and rows #21-#26.

## Root Cause

CRF-053 fixed the defect in the Ruby scanner only. The JS file states that its rules are "kept identical to the Ruby Scanner" and ADR-058 says the rules are implemented in both languages, but the fix was scoped to the file the review named, and the shared contract table was not extended, so nothing forced the JS side to change. This is the shared-code-path rule in AGENTS.md (SF-003/SF-015: grep every caller/copy of the path) and CRF-051's "one table copied row by row" rule, both not applied.

## Prevention

When fixing a rule that has a declared twin implementation (a comment like "kept identical to", an ADR naming both languages), fix and test both in the same change, and add the new cases to the shared contract table before writing either test.

**Promoted to**: Not yet
