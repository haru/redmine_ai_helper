---
description: "Execute .devcontainer/regression-check.sh to verify code quality and tests"
---

# Run Regression Check

Run the project's regression check script to verify YARD documentation coverage,
RuboCop style compliance, and the full test suite after implementation.

## Behavior

This command executes `.devcontainer/regression-check.sh` from the project root.
The script runs:
1. `yard stats --list-undoc` — documentation coverage check
2. `rubocop` — Ruby style linting
3. `bundle exec rake redmine:plugins:test` — full test suite

## Execution

Run the following command from the project root
(`/usr/local/redmine/plugins/redmine_ai_helper`):

```bash
.devcontainer/regression-check.sh
```

If the project root cannot be determined, use the absolute path:

```bash
/usr/local/redmine/plugins/redmine_ai_helper/.devcontainer/regression-check.sh
```

## Result Handling

- **Exit code 0**: All checks passed. Report success and continue.
- **Non-zero exit code**: One or more checks failed. Report the failure output
  and halt with a clear summary of what failed (documentation, linting, or tests).

## Graceful Degradation

- If the script is not executable, attempt `chmod +x .devcontainer/regression-check.sh`
  then retry once.
- If `rubocop` reports offenses, list the offending files and suggest running
  `/rubocop` skill to auto-fix them.
- If tests fail, list the failing test names and suggest investigating before
  committing.
