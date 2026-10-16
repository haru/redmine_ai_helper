# CRF-035: Table class tests pinned Redmine-version markup, matched the wrong element and had narrow negative checks

**Date**: 2026-10-16
**Source**: Local AI review (`/speckit-review-run`, code, tests and simplify agents)
**Feature**: branch `bugfix/076-fix-health-report-table-style`
**Files**: test/unit/ai_helper_helper_test.rb, test/functional/ai_helper_dashboard_controller_test.rb, test/javascript/project_health/ai_helper_health_report_layout_css.test.js
**Category**: test-gap
**Related**: CRF-024, CRF-033

## Feedback

- The "output is unchanged except for the table class" test compared `md_to_html` with a hard-coded HTML string that contained an asset digest (`/assets/icons-0476c1d7.svg`) and Redmine 7.0 markup, so every other job of the CI matrix (6.0, 6.1, master) would fail.
- The dashboard test "body table has the list class" selected `.ai-helper-health-report-body table.list td` with text `#123`. That selector also contains the hidden original report, which is the only place `#123` appears, so the test checked the wrong table and could not fail for the edited body.
- The CSS negative check listed a fixed set of properties and selectors, so `background-color`, `font-size`, `border-top` or a `thead` rule would pass.
- The stub teardown used `const_defined?` with inheritance, and the new `raise` test checked only the class, not the message or the missing-output case.

## Original Code

```ruby
assert_equal PINNED_NON_TABLE_HTML.chomp, html
```
```ruby
assert_select ".ai-helper-health-report-body table.list td", text: "#123"
```

## Fix

The expected value is now built from the running Redmine (same pipeline without the class, then `<table>` replaced by `<table class="list">`). The dashboard test selects `.ai-helper-health-report-current` and the edited text. The CSS check scans every table-related selector of the two containers and matches property prefixes. The teardown uses `const_defined?(:X, false)`; the raise tests assert the message and cover a missing `:output`.

## Root Cause

The AI captured the output once on the local Redmine (7.0) and pasted it as the expectation, without reading `.github/workflows/build.yml` for the versions the test must pass on. For the functional test it chose a selector from the container name without reading the view, where the original report sits inside the same container. The negative CSS check enumerated spellings instead of scanning the whole region, although CRF-033 already required equivalent spellings.

## Prevention

- A test that compares rendered output must not embed values that come from the Redmine install (asset digests, version-specific markup); build the expectation from the same renderer in the test, or normalize those values.
- Before writing an `assert_select` for one of several similar blocks, open the view and check that the selector matches only the intended block and that the asserted text appears only there.
- A negative CSS/HTML check scans every rule of the region and matches property families by prefix, instead of listing spellings.

**Promoted to**: Not yet
