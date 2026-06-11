---
name: speckit-token-budget-scope
description: 'Build a focused reading manifest for the next workflow step. Names the
  files the agent should load, the sections it can skip, and the running token budget.
  Run this *before* /speckit.plan, /speckit.tasks, or /speckit.implement to keep their
  working context lean.

  '
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: token-budget:commands/scope.md
---

# /speckit.token-budget.scope

The user has invoked `/speckit.token-budget.scope` with arguments: `$ARGUMENTS`.

## Your task

Produce a **reading manifest** the agent will follow on the next core SDD
command. The goal is to load the smallest set of artifact regions that
still covers everything the next phase needs to do its job correctly.

This command **never modifies artifacts**. It only writes one file:
`specs/<feature>/.token-budget/scope-<phase>.md`.

## Inputs

1. Resolve the active feature directory from the current git branch.
2. Determine the target phase from `$ARGUMENTS`:
   - explicit: `plan` | `tasks` | `implement` | `analyze` | `checklist`
   - empty → infer the next phase from which artifacts already exist
     (no plan.md → `plan`; plan.md but no tasks.md → `tasks`; both → `implement`).
3. Load `token-budget-config.yml` — `scope.max_total_tokens` and
   `scope.phase_inputs` are the relevant keys.

## Algorithm

### Step 1 — Candidate set
Start from `scope.phase_inputs[<phase>]` and expand `contracts/` to its
actual files. Add any file the user named explicitly via
`--include=<path>` (comma-separated) and remove any file the user named
via `--exclude=<path>`.

### Step 2 — Prefer compacted
For each candidate, if a compacted version exists (the file does **not**
end in `.full.md` and a sibling `<base>.full.md` exists), use the
compacted version. Note the savings. If only `.full.md` exists, suggest
the user run `/speckit.token-budget.compact` first and continue with the
full version.

### Step 3 — Section pruning
For each artifact, identify sections the **target phase actually consumes**
and mark the rest as "skim". Defaults:

| Phase     | Reads in full                                  | Can skim/skip                              |
|-----------|------------------------------------------------|--------------------------------------------|
| plan      | spec.md (FRs, NFRs, user stories, constraints) | spec.md "Background", "Out of scope"       |
| tasks     | plan.md (Constitution Check, Phase 0/1 outcomes), data-model.md, contracts/* | plan.md "Progress Tracking", "Complexity Tracking" |
| implement | tasks.md (full), plan.md (file paths only), contracts/* | research.md, quickstart.md, spec rationale |
| analyze   | spec.md, plan.md, tasks.md (full)              | research.md, quickstart.md                 |
| checklist | spec.md (FRs, NFRs)                            | everything else                            |

These are heuristics. Look at the actual artifact contents and adjust if a
non-default section clearly carries information the next phase needs.

### Step 4 — Token accounting
Use `estimate_tokens.sh` to count each region's tokens. Sum running total.
If the total exceeds `scope.max_total_tokens`:
- First, downgrade the lowest-priority "read" regions to "skim".
- If still over, flag the overflow and recommend:
  - running `/speckit.token-budget.compact --level=aggressive` on the
    largest contributor; or
  - splitting the next phase into a phased run (per `tasks.md` Phase 1
    only, then Phase 2, etc.).

### Step 5 — Write the manifest
Write `specs/<feature>/.token-budget/scope-<phase>.md` with this exact
shape (replace placeholders, keep the headings):

```markdown
# Reading manifest — phase: <phase>

Generated: <ISO-8601-timestamp>
Active feature: <feature-name>
Token budget: <total>/<max_total_tokens>

## Read in full

- `<path>` — <region>, ~<N> tokens
  - Why: <one-line justification>

## Skim only

- `<path>` — <region>, ~<N> tokens
  - Look for: <what the agent should extract if anything>

## Skip

- `<path>` — ~<N> tokens — reason: <not needed for this phase>

## Notes

<any overflow warnings, missing artifacts, or recommendations>
```

### Step 6 — Tell the agent how to use it

Print, after the manifest is written:

```
Manifest written: specs/<feature>/.token-budget/scope-<phase>.md
Budget: <total>/<max>  (<headroom> tokens free)

To use: when you run /speckit.<phase>, read the manifest first and load
only what it lists under "Read in full". Treat "Skim only" entries as
table-of-contents lookups — read the heading list, then jump to the
named region. Do not load "Skip" entries unless the manifest is wrong;
if it is, update it before proceeding.
```

End the response. Do not produce a long explanation.

## Re-runs

A new manifest overwrites the previous one for the same phase. Manifests
from prior phases (e.g. `scope-plan.md` after the user has moved to
tasks) are kept — they document what was loaded historically and are
useful for audit and for `/speckit.token-budget.usage`.