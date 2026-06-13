---
name: speckit-branch-convention-configure
description: Set up branch and folder naming rules for the current project
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: branch-convention:commands/speckit.branch-convention.configure.md
---

# Configure Branch Convention

Set up configurable naming rules for how `/specify` creates Git branches and spec folder names. Supports ticket IDs, GitFlow prefixes, date formats, and custom patterns.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user may specify a preset (e.g., "gitflow", "ticket", "date") or provide custom patterns directly.

## Prerequisites

1. Verify a spec-kit project exists by checking for `.specify/` directory
2. Check if a convention config already exists at `.specify/branch-convention.yml`

## Outline

1. **Determine convention type**: Based on user input or interactive selection:

   | Preset | Branch Pattern | Folder Pattern | Example Branch | Example Folder |
   |--------|---------------|----------------|----------------|----------------|
   | `default` | `{seq}-{kebab}` | `{seq}-{kebab}` | `003-user-auth` | `003-user-auth` |
   | `gitflow` | `{type}/{seq}-{kebab}` | `{seq}-{kebab}` | `feat/003-user-auth` | `003-user-auth` |
   | `ticket` | `{ticket}-{kebab}` | `{ticket}-{kebab}` | `PROJ-142-user-auth` | `PROJ-142-user-auth` |
   | `date` | `{date}-{kebab}` | `{date}-{kebab}` | `20260408-user-auth` | `20260408-user-auth` |
   | `custom` | User-defined pattern | User-defined pattern | — | — |

2. **Collect configuration**: Build the convention config with these fields:

   ```yaml
   # .specify/branch-convention.yml
   convention:
     branch_pattern: "{type}/{seq}-{kebab}"
     folder_pattern: "{seq}-{kebab}"
     type_prefix:
       feature: "feat"
       bugfix: "fix"
       hotfix: "hotfix"
       refactor: "refactor"
       docs: "docs"
     default_type: "feat"
     seq_padding: 3
     seq_start: 1
     date_format: "YYYYMMDD"
     ticket_pattern: "[A-Z]+-[0-9]+"
     max_length: 60
     separator: "-"
     lowercase: true
   ```

3. **Available tokens**: Document these template tokens for patterns:

   | Token | Description | Example |
   |-------|-------------|---------|
   | `{seq}` | Zero-padded sequence number | `003` |
   | `{kebab}` | Kebab-case feature summary (2-4 words) | `user-auth-flow` |
   | `{ticket}` | Ticket/issue ID (e.g., JIRA, Linear) | `PROJ-142` |
   | `{date}` | Date in configured format | `20260408` |
   | `{type}` | Branch type prefix from type_prefix map | `feat` |
   | `{summary}` | Raw feature summary (spaces allowed) | `user auth flow` |

4. **Write configuration**: Save the convention to `.specify/branch-convention.yml`

5. **Validate existing branches** (optional): If branches already exist, check them against the new convention and report any non-compliant ones.

6. **Report**: Output a summary:
   - Convention type selected
   - Branch pattern and folder pattern configured
   - Example branch name using the new convention
   - Number of existing branches that comply / do not comply
   - Suggest next step: `/speckit.branch-convention.validate` to check compliance, or `/speckit.specify` to create a new feature using the convention

## Rules

- **Never overwrite without confirmation** — if `.specify/branch-convention.yml` already exists, show current config and ask before replacing
- **Branch and folder patterns are independent** — branch may include type prefix (`feat/`) while folder stays flat
- **Backward compatible** — if no convention is configured, spec-kit default behavior (`{seq}-{kebab}`) applies
- **Validate patterns** — ensure configured patterns produce valid Git branch names (no spaces, no special chars except `/`, `-`, `_`)
- **Preserve existing numbering** — sequence numbers continue from the highest existing branch number