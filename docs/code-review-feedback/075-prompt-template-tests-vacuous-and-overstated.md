# CRF-075: Log assertions matched fixed text, a helper absorbed bad input and callers coverage was overstated

**Date**: 2026-10-21
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, types, simplify)
**Feature**: branch `081-fix-prompt-template-validation`
**Files**: test/unit/util/prompt_template_test.rb, test/unit/prompt_templates_variables_test.rb, test/unit/prompt_template_callers_test.rb
**Category**: test-gap
**Related**: CRF-051, CRF-063, CRF-033, CRF-070

## Feedback

tests/simplify/code reviews: `assert_includes logged.first, "a"` matched letters in the fixed log text, and `assert_not_includes ... "path"` searched for a word the code never prints (it prints ` (/x.yml)`), so removing the path or the variable names from the log still passed (confirmed by mutation). The variable-extraction helper did `declared.map(&:to_s).uniq`, absorbing non-String elements and duplicates that production code rejects. The callers test header said the remaining callers ran real templates, but `wiki_summary`, `issue_summary`, `generate_issue_reply`, `suggest_stuff_todo` and the backstories were tested only with `load_prompt` stubbed.

## Original Code

```ruby
assert_includes logged.first, "a"
assert_not_includes logged.first.downcase, "path"
declared: declared.map(&:to_s).uniq
```

## Fix

Log assertions compare the whole line; the helper throws on non-String elements and duplicates (with tests); real-template tests were added for the missing callers and the header lists them accurately. Eight guard mutations were run to confirm the tests fail.

## Root Cause

The AI wrote assertions against what it expected to appear instead of the exact output, did not run the guard-removal check that AGENTS.md requires for new branches, and wrote the coverage claim from memory of the existing tests instead of tracing which ones stub `load_prompt`.

## Prevention

Assert a log/message by equality, not by substring of a short token; for a negative assertion, compare against the exact form the code would print. List the callers a comment claims are covered by grepping their tests for `load_prompt`/`format` stubs. Remove each new guard once and confirm a test fails.

**Promoted to**: Not yet
