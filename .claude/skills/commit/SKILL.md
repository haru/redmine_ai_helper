---
name: "commit"
description: "Stage the current changes and create a git commit with a properly formatted English message. Use whenever the user asks to commit, save, or check in their work. Picks a Conventional-Commits-style prefix (fix:, feat:, refactor:, docs:, test:, chore:, style:, perf:) based on the actual diff, keeps the first line a concise summary, and adds a bullet list of details only when the change touches several things."
argument-hint: "Optional: additional context about what changed, or which files to include"
user-invocable: true
disable-model-invocation: false
---

# Commit

Stage the outstanding changes and create a single git commit with an English message that follows this project's format.

## User Input

```text
$ARGUMENTS
```

Consider any additional context from the user input (e.g. "only commit the tool changes", "this is a bug fix") before proceeding.

## Procedure

### Step 1: Survey the Changes

Run in parallel:
- `git status` — see tracked and untracked files
- `git diff` and `git diff --staged` — see the actual content changes
- `git log --oneline -10` — match the repository's existing commit message tone

### Step 2: Stage the Changes

Stage the modified and new files that belong to this piece of work (`git add <files>`, or `git add -A` when everything in the working tree is part of the same change).

Before committing, look at the staged file list once more:
- If anything looks like a secret or credential (`.env`, `*.pem`, `credentials.json`, API keys, etc.), unstage it and warn the user instead of committing it silently.
- If some staged files clearly belong to unrelated, separate work (not what the user is asking to commit right now), leave them out and mention it to the user.

### Step 3: Determine the Commit Type

Look at the diff and classify the change into a prefix:

| Prefix | When to use |
|--------|-------------|
| `fix:` | Bug fix |
| `feat:` | New feature or capability |
| `refactor:` | Restructuring without behavior change |
| `docs:` | Documentation only (README, YARD, locale text) |
| `test:` | Test-only changes |
| `chore:` | Tooling, dependencies, config, housekeeping |
| `style:` | Formatting/whitespace only, no logic change |
| `perf:` | Performance improvement |

If a change spans multiple categories, pick the one that reflects the primary intent.

### Step 4: Write the Commit Message

Format:
- **Line 1**: `<prefix>: <concise summary of the overall change>` — English, imperative mood, no trailing period.
- **If the change is small** (one focused fix, a single file, a short diff): stop at line 1. No body needed.
- **If the change touches several things**: leave a blank line after line 1, then a short bullet list (`- ...`), one line per notable change. Keep bullets brief — what changed, not how.

Example (small change):
```
fix: correct nil check in issue summary cache lookup
```

Example (larger change):
```
feat: add vector model profile support to settings

- add use_vector_model_profile and vector_model_profile_id columns
- update settings UI to select a dedicated vector model profile
- fall back to the default model profile when unset
```

Do not add a `Co-Authored-By` line or any other reference to Claude/AI assistance — this project's convention explicitly excludes that from commit messages.

### Step 5: Commit

Use a heredoc so multi-line messages are formatted correctly:

```bash
git commit -m "$(cat <<'EOF'
<prefix>: <summary>

- <detail 1>
- <detail 2>
EOF
)"
```

Always create a new commit — never `--amend` an existing one unless the user explicitly asks for it.

### Step 6: Confirm

Run `git status` after the commit and report the resulting commit (short hash + first line) to the user. Do not push.

## Notes

- Never push — this skill only commits locally.
- Never use `--no-verify` to skip hooks.
- Write commit messages in plain English regardless of the conversation language.

## Error Handling

- If there is nothing staged and nothing to stage (clean working tree), tell the user there is nothing to commit — do not create an empty commit.
- If a pre-commit hook fails, fix the underlying issue, re-stage, and create a **new** commit — do not amend the previous one (the failed commit never happened).
- If secrets or clearly unrelated files are detected among the changes, stop and confirm with the user before including them.
