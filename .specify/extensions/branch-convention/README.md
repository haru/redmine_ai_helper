# spec-kit-branch-convention

A [Spec Kit](https://github.com/github/spec-kit) extension that adds configurable branch and folder naming conventions — supports ticket IDs, GitFlow prefixes, date-based naming, and custom patterns.

## Problem

Spec Kit's `/specify` command creates branches and spec folders using a fixed naming pattern (`003-feature-name`). Teams with existing Git conventions face adoption blockers:

- No support for GitFlow prefixes (`feat/`, `fix/`, `hotfix/`)
- No way to include ticket/issue IDs (JIRA, Linear, GitHub Issues)
- No date-based naming option beyond the built-in timestamp mode
- No validation to enforce naming consistency across a team
- No way to fix non-compliant branches after the fact

## Solution

The Branch Convention extension adds three commands that make naming fully configurable:

| Command | Purpose | Modifies Files? |
|---------|---------|-----------------|
| `/speckit.branch-convention.configure` | Set up naming rules with presets or custom patterns | Yes — `.specify/branch-convention.yml` |
| `/speckit.branch-convention.validate` | Check branches and folders against the convention | No — read-only |
| `/speckit.branch-convention.rename` | Fix non-compliant branches and folders | Yes — branches, folders, artifact references |

## Installation

```bash
specify extension add --from https://github.com/Quratulain-bilal/spec-kit-branch-convention/archive/refs/tags/v1.0.0.zip
```

## Presets

Choose from built-in presets or define a custom pattern:

| Preset | Branch Pattern | Example |
|--------|---------------|---------|
| `default` | `{seq}-{kebab}` | `003-user-auth` |
| `gitflow` | `{type}/{seq}-{kebab}` | `feat/003-user-auth` |
| `ticket` | `{ticket}-{kebab}` | `PROJ-142-user-auth` |
| `date` | `{date}-{kebab}` | `20260408-user-auth` |
| `custom` | User-defined | — |

## Template Tokens

| Token | Description | Example |
|-------|-------------|---------|
| `{seq}` | Zero-padded sequence number | `003` |
| `{kebab}` | Kebab-case feature summary | `user-auth-flow` |
| `{ticket}` | Ticket/issue ID | `PROJ-142` |
| `{date}` | Date in configured format | `20260408` |
| `{type}` | Branch type prefix | `feat` |
| `{summary}` | Raw feature summary (spaces allowed) | `user auth flow` |

## Workflow

```
/speckit.branch-convention.configure   ← Set up naming rules (once per project)
       │
       ▼
/speckit.specify                       ← Creates branch using your convention
       │
       ▼
/speckit.branch-convention.validate    ← Check compliance (anytime)
       │
       ▼
/speckit.branch-convention.rename      ← Fix non-compliant branches (if needed)
```

## Commands

### `/speckit.branch-convention.configure`

Interactive setup for naming rules. Choose a preset (`default`, `gitflow`, `ticket`, `date`) or define a custom pattern. Saves configuration to `.specify/branch-convention.yml` with options for:

- Branch and folder patterns (independent)
- Type prefixes (`feat`, `fix`, `hotfix`, `refactor`, `docs`)
- Sequence padding, separators, case rules
- Ticket ID format (regex pattern)
- Maximum branch name length

### `/speckit.branch-convention.validate`

Read-only compliance check across all feature branches and spec folders. Reports:

- Pattern match violations
- Missing type prefixes
- Incorrect sequence padding
- Branch-folder sync mismatches
- Length limit violations

### `/speckit.branch-convention.rename`

Safely renames non-compliant branches and folders:

- Shows a preview plan before making changes
- Requires explicit confirmation (destructive operation)
- Uses `git mv` for folders (preserves history)
- Updates artifact references (spec.md, plan.md, tasks.md headers)
- Handles currently checked-out branch correctly

## Hooks

The extension registers an optional hook:

- **before_specify**: Validates naming convention compliance before creating a new feature branch

## Design Decisions

- **Presets for common patterns** — GitFlow, ticket-based, and date-based naming out of the box
- **Branch and folder patterns are independent** — branch may include `feat/` prefix while folder stays flat
- **Backward compatible** — without configuration, spec-kit default behavior is preserved
- **Safe renaming** — always preview before executing, requires clean working tree
- **No remote operations** — rename only affects local branches and folders, remote updates are manual

## Requirements

- Spec Kit >= 0.4.0

## Related

- Issue [#407](https://github.com/github/spec-kit/issues/407) — Configurable naming convention for /specify branch and specs/ folder (39+ upvotes)

## License

MIT
