---
name: speckit-branch-convention-validate
description: Check all feature branches and spec folders against the configured naming
  convention
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: branch-convention:commands/speckit.branch-convention.validate.md
---

# Validate Branch Convention

Check all existing feature branches and spec folders against the configured naming convention. Reports compliance status and identifies violations.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user may specify a specific branch to validate (e.g., "003-user-auth") or "all" to check everything.

## Prerequisites

1. Verify a spec-kit project exists by checking for `.specify/` directory
2. Load convention config from `.specify/branch-convention.yml`
3. If no convention is configured, use the default pattern (`{seq}-{kebab}` for both branch and folder)

## Outline

1. **Load convention**: Read `.specify/branch-convention.yml` and extract:
   - `branch_pattern` — the expected branch naming pattern
   - `folder_pattern` — the expected spec folder naming pattern
   - Token definitions (seq_padding, separator, lowercase, etc.)

2. **Collect branches and folders**: Gather all feature-related items:
   - **Git branches**: List all local branches matching spec-kit patterns (exclude `main`, `master`, `develop`)
   - **Spec folders**: List all directories under `specs/`
   - **Match pairs**: Associate each branch with its corresponding spec folder

3. **Validate each item**: For every branch and folder, check:

   | Check | Rule | Example Violation |
   |-------|------|-------------------|
   | Pattern match | Branch matches `branch_pattern` structure | `user-auth` missing sequence number |
   | Type prefix | If pattern includes `{type}`, prefix must be in `type_prefix` map | `feature/003-auth` instead of `feat/003-auth` |
   | Sequence format | `{seq}` must be zero-padded to `seq_padding` digits | `3-auth` instead of `003-auth` |
   | Length limit | Branch name must not exceed `max_length` characters | `003-very-long-branch-name-that-exceeds-limit...` |
   | Case rule | If `lowercase: true`, no uppercase characters (except ticket IDs) | `003-User-Auth` |
   | Separator | Words must use configured `separator` | `003_user_auth` when separator is `-` |
   | Branch-folder sync | Branch name and folder name must be derivable from same source | Branch `feat/003-auth` but folder `004-auth` |
   | Ticket format | If pattern includes `{ticket}`, must match `ticket_pattern` regex | `proj-142` when pattern requires `[A-Z]+-[0-9]+` |

4. **Output compliance report**:

   ```markdown
   # Branch Convention Compliance Report

   **Convention**: {preset name or "custom"}
   **Branch pattern**: {branch_pattern}
   **Folder pattern**: {folder_pattern}

   ## Results

   | Branch | Folder | Status | Issues |
   |--------|--------|--------|--------|
   | feat/003-user-auth | 003-user-auth | ✅ Compliant | — |
   | 004-chat-system | 004-chat-system | ⚠️ Non-compliant | Missing type prefix |
   | feat/5-api | 5-api | ⚠️ Non-compliant | Sequence not zero-padded |

   ## Summary
   - **Total**: {N} branches
   - **Compliant**: {X} ✅
   - **Non-compliant**: {Y} ⚠️
   - **Orphaned folders** (no branch): {Z}

   ## Recommended Actions
   1. Run `/speckit.branch-convention.rename` to fix non-compliant items
   ```

5. **Report**: Output the compliance report. Do not modify any files — this command is read-only.

## Rules

- **Read-only** — this command never modifies any files or branches
- **Always show all items** — include compliant and non-compliant for full visibility
- **Be specific about violations** — explain exactly which rule was violated and what the correct name should be
- **Handle missing config gracefully** — if no convention is configured, validate against the default pattern and note that no custom convention has been set