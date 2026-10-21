# CRF-072: PromptTemplate validated input_variables but not the rest of its YAML boundary

**Date**: 2026-10-21
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, types, simplify)
**Feature**: branch `081-fix-prompt-template-validation`
**Files**: lib/redmine_ai_helper/util/prompt_template.rb, test/unit/util/prompt_template_test.rb
**Category**: convention-violation
**Related**: CRF-009, CRF-050, CRF-055

## Feedback

types/code/errors/comments reviews: `initialize` checked only `input_variables`; `template` (nil, number, array), a non-Hash YAML root, a `null` `input_variables`, duplicate or malformed names, a non-String `path`, and String/Symbol duplicate keys passed to `format` were all accepted or failed later with `NoMethodError`/`TypeError` that named no file. The returned arrays/strings were mutable, so the declaration `format` checks could change after construction. The test helper already threw on the first two constructs while production code did not.

## Original Code

```ruby
@template = template
@input_variables = input_variables.map { |name| ... name.to_s }
yaml = YAML.safe_load(File.read(file_path))
new(template: yaml["template"], input_variables: yaml["input_variables"] || [], path: file_path)
```

## Fix

`initialize` now requires String `template`, String/nil `path`, a unique Array of valid-placeholder String/Symbol names, and freezes the results. `load_from_path` requires a Hash root, reads `input_variables` with `fetch`, and logs the path before re-raising. `format` rejects String/Symbol duplicate keys. Each guard was removed once to confirm a test fails.

## Root Cause

The spec (research R-003) scoped validation to `input_variables` and marked `template` validation out of scope as YAGNI, and the AI followed the spec without applying AGENTS.md's rule that data read from a file is boundary input and a value object validates every documented invariant. The test helper for the same files had been written more strictly than production code, but the two were not compared.

## Prevention

When a value object is built from file data, list every field of the file and every constructor argument and validate each one in `initialize`/the loader (type, grammar, uniqueness, root shape), even when the spec only names one field. When a test helper parses the same source as production code, give production code the same checks.

**Promoted to**: Not yet
