---
name: speckit-branch-convention-rename
description: Rename non-compliant branches and spec folders to match the configured
  convention
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: branch-convention:commands/speckit.branch-convention.rename.md
---

# Rename to Convention

Rename non-compliant Git branches and spec folders to match the configured naming convention. Handles both branch renaming and folder moving with full safety checks.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user may specify a specific branch to rename (e.g., "004-chat-system") or "all" to rename everything non-compliant.

## Prerequisites

1. Verify a spec-kit project exists by checking for `.specify/` directory
2. Load convention config from `.specify/branch-convention.yml`
3. If no convention is configured, inform the user and suggest running `/speckit.branch-convention.configure` first
4. Verify the working tree is clean (no uncommitted changes) — renaming with dirty state risks data loss

## Outline

1. **Run validation first**: Execute the same checks as `/speckit.branch-convention.validate` to identify all non-compliant branches and folders.

2. **Build rename plan**: For each non-compliant item, compute the correct name:

   | Current Name | Convention | New Name | Action |
   |-------------|------------|----------|--------|
   | `004-chat-system` | `{type}/{seq}-{kebab}` | `feat/004-chat-system` | Rename branch, keep folder |
   | `5-api` | `{seq}-{kebab}` (pad 3) | `005-api` | Rename branch + move folder |
   | `PROJ142-auth` | `{ticket}-{kebab}` | `PROJ-142-auth` | Rename branch + move folder |

3. **Present the rename plan**: Show a preview table before making any changes:

   ```markdown
   # Rename Plan

   | # | Current Branch | New Branch | Current Folder | New Folder |
   |---|---------------|------------|----------------|------------|
   | 1 | 004-chat-system | feat/004-chat-system | 004-chat-system | 004-chat-system (unchanged) |
   | 2 | 5-api | feat/005-api | 5-api | 005-api |

   **Actions**: {N} branches to rename, {M} folders to move
   ```

4. **Confirm with user**: Ask for explicit confirmation before proceeding. This is a destructive operation.

5. **Execute renames** (after confirmation): For each item in the plan:
   - **Rename spec folder**: `git mv specs/{old} specs/{new}` (preserves git history)
   - **Update internal references**: Search spec.md, plan.md, tasks.md for references to the old folder/branch name and update them
   - **Rename git branch**: `git branch -m {old} {new}`
   - **Update tracking**: If branch tracks a remote, inform user to update remote separately

6. **Update references in artifacts**: After renaming, scan all spec artifacts for stale references:
   - `spec.md` header metadata (branch name field)
   - `plan.md` header metadata
   - `tasks.md` header metadata
   - Any cross-references between features

7. **Report**: Output a summary:
   - How many branches were renamed
   - How many folders were moved
   - How many artifact references were updated
   - Any items that could not be renamed (e.g., currently checked-out branch conflicts)
   - Suggest next step: `/speckit.branch-convention.validate` to confirm all items are now compliant

## Rules

- **Never rename without confirmation** — always show the plan first and wait for explicit approval
- **Clean working tree required** — refuse to rename if there are uncommitted changes
- **Use git mv for folders** — preserves git history and tracking
- **Update all references** — scan artifacts for old names and update to new names
- **Never rename main/master/develop** — only rename spec-kit feature branches
- **Handle checked-out branch** — if the current branch needs renaming, rename it last using `git branch -m`
- **Remote branches are informational only** — report that remote branches need manual update (`git push origin :{old} {new}`) but do not push automatically