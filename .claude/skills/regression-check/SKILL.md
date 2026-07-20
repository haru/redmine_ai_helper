---
name: regression-check
description: Run the full regression suite for the redmine_ai_helper plugin (YARD doc coverage, RuboCop, and the plugin test suite) via .devcontainer/regression-check.sh
---

# Regression Check

Run the plugin's full regression check: YARD documentation coverage, RuboCop linting, and the complete Minitest suite.

## Workflow

### Step 1: Run the regression script

```bash
sh -x .devcontainer/regression-check.sh
```

The script (`.devcontainer/regression-check.sh`) does the following, in order, aborting on the first failure (`set -ex`):

1. `cd` into the plugin root
2. `yard stats --list-undoc | tee /dev/stderr | grep -q "100.00%"` — fails if documentation coverage drops below 100%
3. `rubocop` — fails on any offense
4. `cd /usr/local/redmine` then `bundle exec rake redmine:plugins:test` — runs the full Redmine test suite (all plugins, not just `NAME=redmine_ai_helper`)

### Step 2: Triage failures

- **YARD gap**: find the newly undocumented module/class/method/constant/attribute and add a doc comment.
- **RuboCop offense**: fix per the `rubocop` skill's guidelines (see `.claude/skills/rubocop/SKILL.md`); never relax `.rubocop.yml` thresholds without explicit user approval.
- **Test failure/error**: investigate the failing test, fix the underlying code (never disable or delete the test to make it pass), then re-run.

### Step 3: Re-run until clean

Re-run the script after each fix until it exits 0 with:
- `100.00% documented`
- `no offenses detected`
- `0 failures, 0 errors, 0 skips`

## Notes

- Must be run from a shell that can `cd` into `/usr/local/redmine` — the script assumes the plugin lives at `/usr/local/redmine/plugins/redmine_ai_helper`.
- This runs the *entire* Redmine test suite (all plugins), which takes noticeably longer than `rake redmine:plugins:test NAME=redmine_ai_helper`. Use the narrower `NAME=` form for quick iteration while fixing a single test, and this skill for the final full check.
