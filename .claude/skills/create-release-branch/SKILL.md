---
name: "create-release-branch"
description: "Create a release branch for a given version. Use when you want to start a release, cut a release branch, or bump the version for a new release. Creates release/<version> from develop, updates version.rb, and commits the version bump."
argument-hint: "The release version, e.g. 3.3.0"
user-invocable: true
disable-model-invocation: false
---

# Create Release Branch

Create a `release/<version>` branch from `develop`, bump the version in `version.rb`, and commit the change.

## User Input

```text
$ARGUMENTS
```

The user input should contain the target release version (e.g. `3.3.0`). If no version is provided, ask the user which version to release before proceeding.

## Procedure

### Step 1: Confirm the Current Version

Read `version.rb` and note the current `VERSION` value. Confirm the requested version is different and follows semantic versioning (`MAJOR.MINOR.PATCH`).

### Step 2: Check for an Existing Release Branch

Run `git branch -a | grep release` to check whether a `release/<version>` branch already exists.
- If it already exists, stop and report it to the user instead of recreating it.

### Step 3: Create the Release Branch

Create the branch from `develop`:

```
git checkout -b release/<version> develop
```

### Step 4: Bump the Version

Edit `version.rb` and update the `VERSION` constant to the new `<version>`.

```ruby
module RedmineAiHelper
  VERSION = "<version>"
end
```

### Step 5: Commit the Version Bump

Stage **only** `version.rb` (do not include unrelated changes such as `.claude/settings.json`) and commit:

```
git add version.rb
git commit -m "Bump version to <version>"
```

Do not push. Report the branch name and commit to the user.

## Notes

- Follow the project rule: never push without explicit user instruction.
- Commit messages must be plain English with no reference to Claude Code.
- Stage only the version bump; leave any other working-tree changes untouched.
- After this skill, the `create-pull-request` skill can open the release PR against `main`.

## Error Handling

- If `version.rb` is missing or the `VERSION` constant cannot be found, stop and report it.
- If the working tree has the release branch already checked out or the branch exists, do not overwrite — report the current state.
- If the requested version is not valid semver, ask the user to confirm before proceeding.
