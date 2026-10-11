---
name: "record-spec-feedback"
description: "Record a user's correction of an AI-written specification in docs/spec-feedback/ as an append-only entry with root-cause analysis. Use right after applying a user-requested fix to spec.md, plan.md, tasks.md, or a design document (AGENTS.md and the constitution require this), or when the user asks to log spec feedback. Skips typo-only and wording-only fixes."
argument-hint: "Optional: the feedback to record, the feature/artifact, or extra context about why the original was wrong"
user-invocable: true
disable-model-invocation: false
---

# Record Spec Feedback

Record a correction the user requested on an AI-written specification, analyze why the AI wrote it that way, and derive a rule that prevents the same mistake next time.

## User Input

```text
$ARGUMENTS
```

Consider any context from the user input (which feedback to record, which feature, the user's own view of the cause) before proceeding.

## Procedure

### Step 1: Read the Rules

Read `docs/spec-feedback/README.md`. It defines what to record, the root-cause categories, the template, and the index. Follow it; this skill only describes the workflow.

### Step 2: Collect the Feedback

From the conversation and the working tree, identify:

- The user's correction request (their words, translated faithfully into English if needed)
- The affected feature (`specs/NNN-...` directory or branch) and artifact file
- The original AI-written text and the corrected text — use `git diff` on the artifact, or the conversation history when the file is not tracked (`specs/` is gitignored)

Record only corrections that have been applied. If the fix is not applied yet, apply it first.

Stop without recording if every point is a typo fix or a wording change that does not change meaning, and tell the user why.

If the request contains several points, group them by root cause: one entry per root cause.

### Step 3: Check Existing Entries

Scan the index in the README and open entries with the same category or a similar topic. If an existing entry describes the same pattern, list it under **Related**.

### Step 4: Analyze the Root Cause

Answer concretely:

- What did the AI base the original text on (request wording, an existing spec, the code, a guess)?
- What should it have read or asked instead — name the file, wiki page, ADR, or question?
- Why did it not do so (information absent, ambiguity not noticed, convention not documented, over-generalization)?

Pick the category from the README table. Use `other` only with an explanation.

### Step 5: Write the Prevention Rule

Write a rule that is concrete and checkable at spec-writing time (e.g. "When a spec introduces a new setting, state its default; ask the user if the request does not give one" — not "be more careful"). Set **Promoted to** to `Not yet` unless the rule is actually added to a durable place.

### Step 6: Create the Entry

1. Find the highest existing number in `docs/spec-feedback/` and add one (start at `001`).
2. Create `docs/spec-feedback/NNN-short-title.md` from the template, in English, with today's date.
3. Append a row to the README index: `| [SF-NNN](./NNN-short-title.md) | Title | category | feature | Not yet |`.

Never edit or delete existing entries, except for updating the **Promoted to** field in Step 7.

### Step 7: Propose Promotion When It Recurs

If the new entry has one or more **Related** entries (the pattern has occurred at least twice), propose to the user where the prevention rule should be promoted (AGENTS.md, the constitution, a skill) and show the proposed text. Do not change those files without the user's approval. After the approved rule is added, update the entry's **Promoted to** field and the matching index cell to name the destination.

### Step 8: Report

Tell the user the created file, the category, the prevention rule, and any promotion proposal. Do not commit.

## Notes

- Write entries in English regardless of the conversation language.
- Keep excerpts short, but make each entry self-contained: `specs/` is gitignored, so quote the lines needed to understand the correction instead of linking to the artifact.
