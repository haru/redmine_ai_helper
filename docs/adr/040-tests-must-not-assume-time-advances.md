# ADR-040: Tests must not assume time advances under Redmine's frozen test clock

**Date**: 2026-09-29
**Status**: Accepted

## Context

CI builds #1714 and #1715 (PR #461, a dependency bump touching only
`package.json` and `package-lock.json`) both failed on the same test, on
different core branches (`master` and `7.0-stable`):

```
RedmineAiHelper::Vector::VectorDbTest
  "VectorDb add_datas should skip data that is already up-to-date"
unexpected invocation: #<Mock:client>.add_texts(...)
- expected never, invoked once: #<Mock:client>.add_texts(any_parameters)
```

Redmine core recently changed its `test/test_helper.rb` (commit `137c824cab`,
r25150, #44455, merged into `7.0-stable` on 2026-09-28 and also present on
`master` and `6.1-stable`) to freeze the clock for every test:

```ruby
FROZEN_TIME = Time.now.freeze

def before_setup
  travel_to FROZEN_TIME
  super
end
```

`travel_to` truncates to whole seconds, and the clock no longer moves during a
test. In both failed builds, every log line written during the 60–80 second
test run had the same timestamp (for example `23:07:17.000000`).

`VectorDb#add_datas` skips a record only when the source is strictly older
than its vector entry:

```ruby
next if vector_data and data.updated_on < vector_data.updated_at
```

The test saves an issue, registers it, and registers it again, expecting the
second call to skip. With a frozen clock, `issue.updated_on` and
`vector_data.updated_at` are always equal, so the strict comparison is false
and the issue is registered again. The failure is deterministic under the new
core test helper, not a race. It reproduces locally once `/usr/local/redmine`
is updated.

## Decision

1. Fix the test, not the production comparison. After the first `add_datas`,
   explicitly make the vector entry newer than the source:

   ```ruby
   AiHelperVectorData.update_all(updated_at: 1.minute.from_now)
   ```

   This writes a timestamp value only; it does not sleep.

2. As a rule for plugin tests: do not rely on wall-clock time advancing
   between two operations in the same test, and do not rely on records
   created back to back having different timestamps. When a test depends on
   ordering by time, set the timestamps explicitly or advance the clock with
   `travel` / `travel_to`.

## Consequences

- The test is deterministic both with and without core's frozen clock, so it
  passes on every core branch in the CI matrix.
- The full plugin suite passes against the updated core (2934 runs, 0
  failures, 0 errors, 0 skips). No other test currently depends on the clock
  advancing.
- Production behavior is unchanged: an issue updated within the same second
  as its vector registration is still picked up on the next run.
- Future tests that compare timestamps must follow decision 2; otherwise
  they will fail in CI even though they pass against an older local core
  checkout.

## Alternatives Considered

- **Change the production check to `<=`**: rejected. Timestamps are stored at
  one-second precision, so an issue updated in the same second as its vector
  registration would be skipped permanently and its vector entry would go
  stale. The test would pass, but this would hide a real regression risk to
  work around a test-only condition.
- **Re-run CI and treat the failure as a flake**: rejected. The failure is
  deterministic under the frozen clock, so re-running cannot fix it.
- **Undo core's freeze in the plugin's `test_helper.rb` (for example by calling
  `travel_back` in a global `setup`)**: rejected. It would fight core's test
  conventions, could break core helpers and fixtures that rely on
  `FROZEN_TIME`, and would make plugin tests behave differently from core
  tests.
