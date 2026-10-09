---
name: "record-code-review-feedback"
description: "Record code review findings (GitHub Copilot PR review or a local AI review) that led to a code change in docs/code-review-feedback/ as append-only entries with root-cause analysis. Use right after fixing code in response to a review finding (AGENTS.md and the constitution require this), or when the user asks to log review feedback. Skips findings that were not adopted."
argument-hint: "Optional: PR number, review source, or the findings to record"
user-invocable: true
disable-model-invocation: false
---

# Record Code Review Feedback

Record review findings on AI-generated code that resulted in a fix, analyze why the AI wrote the original code, and derive a rule that prevents the same mistake next time.

## User Input

```text
$ARGUMENTS
```

Consider any context from the user input (PR number, which findings, the review source) before proceeding.

## Procedure

### Step 1: Read the Rules

Read `docs/code-review-feedback/README.md`. It defines what to record, the root-cause categories, the template, and the index. Follow it; this skill only describes the workflow.

### Step 2: Collect the Findings

Identify the review source:

- **GitHub Copilot PR review**: determine the PR from the user input or `gh pr view --json number -q .number` on the current branch, then fetch Copilot's review comments:

  ```bash
  gh api repos/{owner}/{repo}/pulls/<PR>/comments --paginate \
    --jq '.[] | select(.user.login == "Copilot") | {id, path, line, html_url, body}'
  ```

- **Local AI review** (`/code-review`, `speckit-review-*`, etc.): use the findings reported earlier in the conversation.

For each finding, check whether it led to a code change (`git diff`, `git log -p` on the affected files, or the conversation). Keep only adopted findings. Skip typo-only and formatting-only fixes.

If nothing remains, stop and tell the user there is nothing to record.

Group the remaining findings by root cause: one entry per root cause.

### Step 3: Check Existing Entries

Scan the index in the README and open entries with the same category or touching the same files/area. If an existing entry describes the same pattern, list it under **Related**.

### Step 4: Analyze the Root Cause

Answer concretely:

- What did the AI base the original code on (a nearby pattern, the spec, a guess, a generic idiom)?
- What should it have checked — name the AGENTS.md rule, constitution principle, ADR, existing helper, or Redmine API?
- Why did it not do so (rule not documented, rule documented but not consulted, edge case not considered, tests did not cover it)?

Pick the category from the README table. Use `other` only with an explanation.

### Step 5: Write the Prevention Rule

Write a rule that is concrete and checkable at code-generation time (e.g. "Tools that take a project ID must return the same error for missing and invisible projects" — not "check permissions carefully"). Set **Promoted to** to `Not yet` unless the rule is actually added to a durable place.

### Step 6: Create the Entry

1. Find the highest existing number in `docs/code-review-feedback/` and add one (start at `001`).
2. Create `docs/code-review-feedback/NNN-short-title.md` from the template, in English, with today's date. Include the review comment URL and the fix commit hash when available.
3. Append a row to the README index: `| [CRF-NNN](./NNN-short-title.md) | Title | category | source | Not yet |`.

Never edit or delete existing entries — only add the index row.

### Step 7: Propose Promotion When It Recurs

If the new entry has one or more **Related** entries (the pattern has occurred at least twice), propose to the user where the prevention rule should be promoted (AGENTS.md, the constitution, an ADR, a skill) and show the proposed text. Do not change those files without the user's approval.

### Step 8: Report

Tell the user the created files, categories, prevention rules, and any promotion proposal. Do not commit.

## Notes

- Write entries in English regardless of the conversation language.
- Keep code excerpts short (the relevant lines only).
- If `gh` fails (not authenticated, API error), report the error to the user instead of guessing the review content.
