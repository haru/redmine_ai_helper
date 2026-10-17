---
name: "create-pull-request"
description: "Create a pull request from the current branch. Use when you want to open a PR, submit changes, or create a pull request. Handles release branches (release/**) and feature/fix branches differently, setting the correct base branch, title, description, and labels automatically."
argument-hint: "Optional: additional context or instructions for the PR"
user-invocable: true
disable-model-invocation: false
---

# Create Pull Request

Create a pull request from the current branch with appropriate title, description, base branch, and labels.

## User Input

```text
$ARGUMENTS
```

Consider any additional context from the user input before proceeding.

## Procedure

### Step 1: Identify Current Branch

Run `git branch --show-current` to get the current branch name.

### Step 2: Determine Branch Type

Check if the branch name starts with `release/`:
- **Release branch** (`release/**`): follow the Release Branch workflow below
- **All other branches**: follow the Feature/Fix Branch workflow below

---

## Release Branch Workflow (`release/**`)

### Base Branch
`main`

### Title
Extract the version from the branch name.
- Branch `release/1.2.3` → title: `Release 1.2.3`
- Format: `Release <version>`

### Description
Use the same text as the title. No additional details needed.
```
Release <version>
```

### Labels
None — do not add any labels.

### Create PR
Use the GitHub MCP tool (`mcp_github_mcp_se_create_pull_request`) as the primary method.
If unavailable, fall back to `gh pr create`:
```
gh pr create --base main --title "Release <version>" --body "Release <version>"
```

---

## Feature/Fix Branch Workflow (non-release branches)

### Base Branch
`develop`

### Title

**The PR title is copied verbatim into the release notes.** Readers are plugin users and administrators, not developers. Write the title for them: it must make sense without seeing the code, the branch, or the PR description.

Title rules:
- Describe the **user-visible effect** (what the user can now do, or what problem no longer occurs), not the implementation. Use the vocabulary of the UI and features (e.g. "health report", "model profile", "custom commands"), not class, method, file, or gem names.
- Start with an imperative verb (`Add`, `Fix`, `Improve`, `Support`, `Allow`, `Remove`). For bug fixes, state the symptom that is fixed, e.g. `Fix health report tables rendering without borders`.
- Be specific enough to stand alone in a list of ~20 entries; avoid vague titles such as `Fix bug`, `Update settings`, `Refactor agents`.
- One line, ideally under 70 characters. No issue numbers, no branch or spec numbers (e.g. `076-`), no author names, no emojis, no trailing period.
- Changes with no user-visible effect (refactoring, tests, CI, internal docs) get a plain, honest title such as `Refactor ...` / `Improve test coverage for ...`; do not inflate them into features.

Good: `Add model profile copy to the admin settings screen`
Bad: `Implement ModelProfilesController#copy and add 010 spec`

How to derive the title:

**If the branch is a Spec Kit branch** (branch name matches pattern used by speckit, e.g., `feature/NNN-*` or follows the speckit branch convention):
1. Locate the corresponding `spec.md` file under `specs/<branch-folder>/` (fall back to `.specify/<branch-folder>/`)
2. Read the user stories / summary in spec.md and identify what the user gains or what is fixed
3. Write the title following the rules above

**If the branch is NOT a Spec Kit branch**:
1. Run `git log develop..HEAD --oneline` to list commits on this branch
2. Run `git diff develop...HEAD --stat` to see changed files
3. Work out the user-visible effect of the changes, then write the title following the rules above

Before creating the PR, re-read the title as an end user scanning the release notes: if it needs the code to be understood, rewrite it.

### Related GitHub Issue

Determine whether this PR fixes or implements an existing GitHub issue. Look for issue references in these sources, in order:

1. **User input** (`$ARGUMENTS`): e.g., `#123`, `issue 123`, or a GitHub issue URL.
2. **Commit messages**: run `git log develop..HEAD --format=%B` and look for `#123`, `Fixes #123`, `Closes #123`, or GitHub issue URLs.
3. **Spec Kit artifacts** (Spec Kit branches only): look for GitHub issue URLs or `#123` references in the feature's `spec.md` (e.g., in the input/description section).
4. **Branch name**: only a pattern explicitly naming an issue, such as `issue-123`, `issue/123`, or `fix/#123`. Do not treat the Spec Kit sequential prefix (e.g., `062-` in `062-optional-temperature`) as an issue number — it is a feature counter, not an issue ID.

For each candidate number, verify it is an existing **issue** (not a pull request) in this repository using the GitHub MCP tool (`issue_read`) or `gh issue view <number> --json number,title,state`. Discard candidates that do not exist or are pull requests.

If no reference is found but the changes clearly address a known problem, you may search open issues (GitHub MCP `search_issues` or `gh issue list --search "<keywords>" --state open`). Only link a search result if it clearly matches the changes; if uncertain, ask the user to confirm rather than guessing, since a wrong link can auto-close an unrelated issue.

If no related issue is identified, skip the issue line in the description.

### Description

Run `git diff develop...HEAD --stat` and `git log develop..HEAD --oneline` to understand the changes.

Write a short English description using a bullet list:
```markdown
## Changes

- <concise description of change 1>
- <concise description of change 2>
- ...
```

Keep each bullet to one line. Focus on *what* changed and *why*, not implementation details.

If a related issue was identified, put it at the top of the description using a GitHub closing keyword so the PR is linked to the issue:
```markdown
Fixes #<issue-number>

## Changes

- ...
```

- Use `Fixes #N` for bug fixes and `Closes #N` for features/enhancements.
- For multiple issues, put each on its own line (e.g., `Fixes #12` and `Fixes #34`).
- If the PR only partially addresses the issue, use `Related to #N` instead so the issue is not auto-closed.

### Labels

Analyze the changes and select one or more labels from:

| Label | When to use |
|-------|-------------|
| `enhancement` | New feature or improvement |
| `bug` | Bug fix |
| `documentation` | Docs-only change (README, YARD, locales) |

Select all that apply. If a label does not exist in the repository, skip it rather than failing.

### Create PR

Use the GitHub MCP tool (`mcp_github_mcp_se_create_pull_request`) as the primary method to create the PR.
If the MCP tool is unavailable, fall back to `gh pr create`:
```
gh pr create \
  --base develop \
  --title "<title>" \
  --body "<description>" \
  --label "<label1>" \
  --label "<label2>"
```

---

## Error Handling

- If `git log` or `git diff` returns empty (branch has no commits ahead of base), inform the user there is nothing to PR.
- If the spec.md file cannot be found for a Spec Kit branch, fall back to deriving the title from git commits (still following the release-notes title rules).
- If label creation fails (label does not exist), omit that label and proceed.
- If the PR already exists for this branch, report the existing PR URL instead of creating a duplicate.
