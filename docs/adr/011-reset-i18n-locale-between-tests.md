# ADR-011: Reset `I18n.locale` before every test

**Date**: 2026-08-02
**Status**: Accepted

## Context

CI intermittently failed on the `6.1-stable` Redmine core matrix leg with
assertions expecting English strings but receiving Japanese ones, e.g.:

```
Expected ["を入力してください"] to include "cannot be blank".
Expected ["はすでに存在します"] to include "has already been taken".
Expected /CRITICAL SECURITY CONSTRAINTS/i to match "# 役割とタスクの定義..."
```

These failures were not localized to one test file; they hit unrelated tests
(`AiHelperSummaryCacheTest`, `VectorDestroyRakeTest`, `IssueAgentTest`) and
only appeared for some random test-order seeds, never reliably.

Root cause: Redmine's `ApplicationController#set_localization` sets
`I18n.locale` as a process-global for the duration of the request and does not
reset it afterward. Plugin tests that flip a user's `language` to `"ja"` and
then issue a controller request (e.g.
`ai_helper_controller_test.rb`'s `@user.update_column(:language, "ja")` case)
leave `I18n.locale` set to `:ja` for the rest of the test process. Any later
test in the same worker that asserts on English strings then fails, purely
because of test execution order.

Redmine core fixed this exact issue upstream (redmine#44116, commit
`a01ff5a5a`) by resetting `I18n.locale` in a `setup` block in
`test/test_helper.rb`. That fix landed after `6.1-stable` was cut and has not
been backported to it, so the CI leg pinned to `6.1-stable` still exhibits the
leak even though newer core branches (e.g. `7.0-stable`) do not.

## Decision

Add the same reset as a plugin-level `setup` hook in
`test/test_helper.rb`, independent of whether the core branch under test
carries the upstream fix:

```ruby
ActiveSupport::TestCase.setup do
  ::I18n.locale = ::I18n.default_locale # rubocop:disable Rails/I18nLocaleAssignment
end
```

## Consequences

- Plugin tests no longer depend on which core branch (and therefore which
  fix set) the CI matrix happens to check out; locale leakage cannot cross
  test boundaries within the plugin's own suite regardless of run order.
- The hook duplicates a fix that already exists upstream on newer branches;
  once the CI matrix drops `6.1-stable` this becomes redundant but harmless
  (it just reasserts the default locale core would already have reset).
- `Rails/I18nLocaleAssignment` flags direct `I18n.locale=` assignment in
  favor of `I18n.with_locale`; a block form does not fit a per-test global
  reset, so the cop is disabled inline for this one line, matching how
  Redmine core's own `test/test_helper.rb` handles the identical line.

## Alternatives Considered

- **Wait for `6.1-stable` support to be dropped from the CI matrix**:
  rejected for now — the matrix still targets it, and until it doesn't, CI
  will keep failing sporadically for reasons unrelated to the change under
  review.
- **Fix only the offending test** (`ai_helper_controller_test.rb`) to restore
  `I18n.locale` in a `teardown`: rejected as too narrow. Any future test that
  changes the locale via a controller request or `I18n.locale=` would
  reintroduce the same class of flake; a single global reset covers all of
  them.
- **Wrap the specific test's request in `I18n.with_locale`**: not viable —
  the leak comes from Redmine core's own request-handling code
  (`set_localization`), not from the test's own locale manipulation, so the
  test has no block to wrap.
