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

**If the branch is a Spec Kit branch** (branch name matches pattern used by speckit, e.g., `feature/NNN-*` or follows the speckit branch convention):
1. Locate the corresponding `spec.md` file under `.specify/` (e.g., `.specify/<branch-folder>/spec.md`)
2. Read the spec.md and derive a concise English title from the feature description
3. Title should be imperative and descriptive, e.g., `Add vector model profile support`

**If the branch is NOT a Spec Kit branch**:
1. Run `git log develop..HEAD --oneline` to list commits on this branch
2. Run `git diff develop...HEAD --stat` to see changed files
3. Derive a concise, imperative English title summarizing the changes
4. Example: `Fix issue summary cache invalidation`

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
- If the spec.md file cannot be found for a Spec Kit branch, fall back to deriving the title from git commits.
- If label creation fails (label does not exist), omit that label and proceed.
- If the PR already exists for this branch, report the existing PR URL instead of creating a duplicate.
