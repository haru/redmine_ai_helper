---
name: "create-release-notes"
description: "Generate Redmine.org release notes from a GitHub release tag. Fetches the release, strips emojis/issue numbers/author names, and outputs Textile-formatted text ready to paste into redmine.org."
argument-hint: "The release version tag, e.g. 3.3.0"
user-invocable: true
disable-model-invocation: false
---

# Create Redmine.org Release Notes

Fetch the GitHub release notes for a given version and convert them into Textile format suitable for posting on redmine.org.

## User Input

```text
$ARGUMENTS
```

The user input should contain the release version (e.g. `3.3.0`). If no version is provided, ask the user which version to use before proceeding.

## Procedure

### Step 1: Determine the Version

Extract the version from `$ARGUMENTS`. If absent, ask the user for the target version.

### Step 2: Fetch the GitHub Release Notes

Run:

```bash
gh release view <version> --repo haru/redmine_ai_helper
```

Parse the Markdown body from the output.

### Step 3: Convert to Textile

Transform the Markdown release notes into Textile following these rules:

| Markdown | Textile |
|---|---|
| `## What's Changed` | `h3. What's Changed` |
| `### New Features …` | `h4. New Features` |
| `### Bug Fixes …` | `h4. Bug Fixes` |
| `### Other Changes …` | `h4. Other Changes` |
| `* item` / `- item` | `* item` |

**Cleanup rules (apply in order):**

1. **Remove emojis** — strip all emoji characters (e.g. `:tada:`, Unicode emoji such as 🎉, 🐛, 📝).
2. **Remove GitHub issue/PR references** — delete patterns like `by @author in https://github.com/.../pull/123` or `by @author in https://github.com/.*/issues/\d+`. Also remove standalone ` by @username` suffixes.
3. **Remove author names** — delete any remaining ` by @username` patterns.
4. **Remove hyperlinks** — delete bare GitHub URLs that appear after cleanup (e.g. `https://github.com/...`).
5. **Remove the "Full Changelog" line** — drop the line starting with `**Full Changelog**`.
6. **Trim trailing whitespace** from each bullet.

### Step 4: Prepend the Download Section

Add a download section at the top:

```
h3. Download

https://github.com/haru/redmine_ai_helper/releases/tag/<version>
```

### Step 5: Output the Result

Print the complete Textile text to the user so they can copy and paste it into redmine.org. Do not write it to any file.

## Expected Output Format

```
h3. Download

https://github.com/haru/redmine_ai_helper/releases/tag/<version>

h3. What's Changed

h4. New Features

* <feature description>
* <feature description>

h4. Bug Fixes

* <fix description>

h4. Other Changes

* <change description>
* <change description>
```

## Notes

- Output must be **Textile**, not Markdown. redmine.org does not render Markdown.
- Never include emoji — redmine.org does not support them.
- Never include GitHub issue/PR numbers (`#123`) — they would be interpreted as redmine.org issue numbers.
- Never include author names — GitHub usernames are irrelevant on redmine.org.
- Do not write the output to any file; display it in the conversation only.
