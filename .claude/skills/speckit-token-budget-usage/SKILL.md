---
name: speckit-token-budget-usage
description: 'Show token usage for every SDD artifact in the active feature, the projected
  context window for each upcoming phase, and the savings already realized by token-budget
  (full backups vs current files).

  '
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: token-budget:commands/usage.md
---

# /speckit.token-budget.usage

The user has invoked `/speckit.token-budget.usage` with arguments: `$ARGUMENTS`.

## Your task

Inspect the active feature directory and produce a one-screen token-usage
dashboard. Read-only — never modify artifacts.

## Algorithm

### Step 1 — Resolve scope
Default scope: the active feature (from current git branch). If
`$ARGUMENTS` contains `--all`, walk every feature under `specs/`. If it
contains `--feature=<name>`, target that feature.

### Step 2 — Enumerate artifacts
For each artifact present, record:
- path (relative to feature directory)
- byte size
- estimated token count (use `estimate_tokens.sh`)
- whether a `.full.md` backup exists, and its token count if so
- whether the file carries the `<!-- token-budget: compacted -->` marker

Standard artifact set: `constitution.md`, `spec.md`, `plan.md`,
`research.md`, `data-model.md`, `quickstart.md`, `tasks.md`, every file
in `contracts/`, plus any extra `.md` files in the feature root (treat
as auxiliary).

### Step 3 — Project per-phase budgets
For each upcoming phase the feature has not yet completed, sum the
artifacts it would normally consume (from `scope.phase_inputs` in
`token-budget-config.yml`). Show two numbers per phase: current size,
and size if every artifact were compacted (estimated as 60% for medium,
45% for aggressive — these are heuristics, not guarantees, and should
be labeled as such).

### Step 4 — Render
Output exactly this layout. Right-align numbers. Use thousands
separators. Pad with spaces, not tabs.

```
Token Budget — feature: <feature-name>
Path: specs/<feature-name>/

Artifact                tokens     vs full       status
─────────────────────────────────────────────────────────────────
constitution.md          1,240          —        baseline
spec.md                  2,310     -52.1%        compacted (medium)
plan.md                  3,580     -41.7%        compacted (medium)
research.md              1,180     -63.1%        compacted (medium)
data-model.md            1,840          —        baseline
contracts/orders.yaml      910          —        schema (not eligible)
contracts/users.yaml       820          —        schema (not eligible)
quickstart.md              640          —        baseline
tasks.md                 4,210          —        baseline
─────────────────────────────────────────────────────────────────
total                   16,730     -27.4% vs uncompacted

Projected phase budgets
                       current    if aggressive compact
plan       (done)            —                       —
tasks      (done)            —                       —
implement                12,560                   ~7,540
analyze                  10,100                   ~6,060

Backups present: spec.full.md, plan.full.md, research.full.md
Concise mode: <on|off>  (memory file: <path>)
```

If `--all` was passed, repeat the artifact table once per feature and
add a final cross-feature roll-up showing the total savings.

### Step 5 — Recommendations (only when warranted)
If any single artifact exceeds 5,000 tokens **and** is not compacted,
append a one-line nudge:

```
Suggestion: tasks.md is 6,140 tokens. /speckit.token-budget.compact tasks
would likely save ~40%.
```

If concise mode is off and the project is large (more than 12k total
tokens), suggest:

```
Suggestion: /speckit.token-budget.concise on  (estimated 5–15% output savings)
```

Only emit suggestions that are actually warranted by the numbers. No
generic advice.

End the response. The dashboard is the deliverable.