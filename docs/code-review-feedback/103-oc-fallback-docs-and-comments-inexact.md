# CRF-103: Open Color fallback ADR and CSS comments were inexact

**Date**: 2026-11-21
**Source**: Local AI review (speckit-review-run: comments, code)
**Feature**: branch `bugfix/087-fix-popup-oc-colors`
**Files**: docs/adr/072-redmine-6-fallbacks-for-open-color-variables.md, assets/stylesheets/ai_helper.css, test/javascript/support/css_rules.js, test/javascript/shared/ai_helper_redmine_version_colors_css.test.js
**Category**: doc-comment
**Related**: CRF-032, CRF-085, CRF-092

## Feedback

- ADR-072 said an invalid-at-computed-value-time declaration "falls back to its
  initial value (transparent)". The property becomes `unset`: `color` inherits,
  `border` and `box-shadow` become none; only backgrounds are transparent.
- The CSS comment cited "Redmine 7 application.css:933-941" for the sticky
  header, but on 7.0-stable the rule is at 930-945. Other line numbers named no
  branch, and "exists only in Redmine 7" excluded later versions.
- The ADR said Redmine 6 shows the same colours as its own elements, but two
  fallbacks (the `:active` background and the Redmine 6.0 shadow) have no Redmine 6
  counterpart. "Every stylesheet" meant only the top level of `assets/stylesheets`.
- A parser comment said "checks below" after the helper moved to its own module,
  the `parseRules` JSDoc listed only some throw cases, and the contract table's
  JSDoc sat above the wrong constant.

## Original Code

```text
... so the property falls back to its initial value (transparent) ...
/* Same shadow as Redmine's #sticky-issue-header (Redmine 7 application.css:933-941). */
```

## Fix

Rewrote the ADR sentence with the `unset` behaviour, named the two exceptions and
the scanned directory, cited `7.0-stable` with the checked line ranges, changed
"only in Redmine 7" to "7.0 and later", and corrected the JSDoc placement and
throw-case lists. Fix commit: not committed yet.

## Root Cause

The AI described the visible symptom (a transparent popup) as the general CSS rule,
and carried line numbers and scope words forward from the pre-change comment
without re-reading Redmine's sources for the branch it now named. It had read the
rule that two values were decided with the maintainer, but did not list them where
the ADR states the guarantee.

## Prevention

When a comment or ADR cites a Redmine file and line, name the branch or tag and
re-read those lines in the same step; state a guarantee with its exceptions and
its scope (which directory, which versions); describe a CSS behaviour from the
specification's rule, not from the one property that showed the bug.

**Promoted to**: Not yet
