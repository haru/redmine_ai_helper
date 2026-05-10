---
name: rubocop
description: Run RuboCop linting and fix offenses for the redmine_ai_helper plugin
---

# RuboCop Check and Fix

Run RuboCop on the plugin codebase, auto-fix what is safe, and manually resolve remaining offenses.

## Workflow

### Step 1: Run RuboCop

```bash
rubocop 2>&1
```

### Step 2: Auto-fix safe offenses

```bash
rubocop -A --except Rails/ActionControllerTestCase 2>&1
```

Exclude `Rails/ActionControllerTestCase` — Redmine plugin tests require `ActionController::TestCase`. Converting to `ActionDispatch::IntegrationTest` breaks the `tests` helper method and other controller-specific APIs.

### Step 3: Manually fix remaining offenses

Address any offenses that remain after auto-correction using the guidelines below.

> **IMPORTANT: Never modify `.rubocop.yml` thresholds (`Max:` values) or `Exclude:` settings without explicit user approval.**
> If offenses cannot be fixed in the source code, report them to the user and ask how to proceed.
> Do not raise `Max:` values, add new `Exclude:` entries, or run `git checkout -- .rubocop.yml` to work around violations.

| Cop | Action |
|-----|--------|
| `Rails/Pluck` | If called on a plain Ruby array (not ActiveRecord), add `# rubocop:disable Rails/Pluck` inline |
| `Rails/RedundantPresenceValidationOnBelongsTo` | If tests assert `errors[:foreign_key_id]`, the explicit validation is needed — add `# rubocop:disable` inline |
| `Rails/I18nLocaleAssignment` | Rewrite `I18n.locale = x` as an `I18n.with_locale(x) { ... }` block |
| Cop disabled project-wide | Add `Enabled: false` under the cop name in `.rubocop.yml` — **only with user approval** |

### Step 4: Run tests to verify

```bash
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper 2>&1 | tail -20
```

Confirm 0 failures and 0 errors before finishing.

## Common Cases

### `Rails/ActionControllerTestCase`

Already disabled in `.rubocop.yml`. No changes needed.

```yaml
Rails/ActionControllerTestCase:
  Enabled: false
```

### `Rails/RedundantPresenceValidationOnBelongsTo`

The implicit `belongs_to` validation puts errors on `:association_name`, not `:foreign_key_id`. If tests check `errors[:project_id]` or `errors[:user_id]`, keep the explicit validation:

```ruby
validates :project_id, presence: true # rubocop:disable Rails/RedundantPresenceValidationOnBelongsTo
validates :user_id, presence: true    # rubocop:disable Rails/RedundantPresenceValidationOnBelongsTo
```

### `Rails/Pluck`

`.pluck` is an ActiveRecord method and does not work on plain Ruby arrays. Disable inline:

```ruby
issue_counts = members_workload.map { |m| m[:assigned_issues] } # rubocop:disable Rails/Pluck
```

### `Rails/I18nLocaleAssignment`

```ruby
# Before
original_locale = I18n.locale
I18n.locale = :ja
# ... test code
ensure
  I18n.locale = original_locale

# After
I18n.with_locale(:ja) do
  # ... test code
end
```
