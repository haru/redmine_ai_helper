---
name: speckit-token-budget-compact
description: 'Compact one or more Spec-Driven Development artifacts in place to reduce
  token cost on subsequent /speckit.* commands. Lossless on requirements, decisions,
  contracts, IDs; strips template scaffolding, examples, and prose padding. The original
  is preserved as <artifact>.full.md the first time an artifact is compacted.

  '
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: token-budget:commands/compact.md
---

# /speckit.token-budget.compact

The user has invoked `/speckit.token-budget.compact` with arguments: `$ARGUMENTS`.

## Your task

Compact one or more SDD artifacts in the active feature so that downstream
spec-kit commands consume fewer tokens, **without losing any requirement,
decision, contract, ID, user story, or acceptance criterion**.

## Inputs

1. Resolve the active feature directory (typically `specs/<NNN-feature-name>/`)
   from the current git branch using the existing spec-kit conventions. If the
   user is not on a feature branch, ask which feature to operate on and stop.

2. Parse `$ARGUMENTS`:
   - empty → compact every artifact in the active feature directory.
   - `spec` | `plan` | `tasks` | `research` | `data-model` | `contracts` |
     `quickstart` | `constitution` → compact only that one (or that group, in
     the case of `contracts`).
   - a relative or absolute path → compact that file.
   - `--level=light|medium|aggressive` → override the configured level for
     this run only.
   - `--dry-run` → report what would change, write nothing.

3. Load `token-budget-config.yml` from the extension directory if present,
   otherwise use the template defaults. The keys you care about are:
   `compact.level`, `compact.preserve_sections`, `compact.drop_sections`,
   `compact.preserve_code_blocks`, `compact.preserve_id_patterns`,
   `compact.keep_full_backup`.

## Algorithm — apply in order, per artifact

### Step 1 — Backup
If `keep_full_backup` is true and `<artifact>.full.md` does not yet exist,
copy the current artifact to `<artifact>.full.md`. Never overwrite an
existing backup. The backup is the source of truth for re-compaction at a
different level later.

### Step 2 — Lossless strips (every level)
- Remove HTML comments left over from templates (`<!-- ... -->`), **except**
  the spec-kit machine-readable markers (e.g. `<!-- INSERT_STATUS_BELOW -->`)
  if present.
- Remove sections whose heading prefix-matches any entry in
  `compact.drop_sections`.
- Collapse runs of 3+ blank lines into a single blank line.
- Remove decorative ASCII separators (`---`, `===`, repeated `*` or `_` runs)
  that are not Markdown horizontal rules between meaningful sections.
- Strip repeated cross-reference reminders that the same artifact already
  states (e.g. "see spec.md FR-001" appearing in three sibling sections — keep
  the first occurrence per section, drop the rest).
- Strip phrase-level filler: "Note that", "It should be noted that",
  "As mentioned above", "For your reference", "Please be aware that",
  "It is important to understand that", and similar leading hedges. Keep
  the substantive clause that follows.

### Step 3 — Medium level (default)
In addition to Step 2:
- Convert prose paragraphs that enumerate items into bullet lists when the
  prose contains "first ... second ... third", "as well as", or comma-
  separated noun clauses. Only when conversion is **lossless** — if in
  doubt, leave the prose alone.
- Collapse multi-sentence paragraphs that restate a single requirement into
  one sentence per requirement.
- For tables that have an "Example" or "Notes" column with prose larger
  than 20 words, condense to ≤ 12 words per cell.

### Step 4 — Aggressive level
In addition to Steps 2–3:
- Drop sections titled "Rationale", "Alternatives Considered", "Background",
  "Motivation" — these are valuable for humans but the decision they justify
  is captured elsewhere in the artifact.
- Drop the leading framing paragraph of each top-level section if a
  structured list immediately follows that conveys the same information.
- Replace prose in "Research" findings with a one-line conclusion plus a
  bulleted evidence list.

### Step 5 — Hard preservation guardrails (every level)
**Never** modify, paraphrase, or remove:
- Any line containing a token that matches `compact.preserve_id_patterns`
  (FR-001, NFR-002, T015, US-003, AC-007, etc.) — keep the line verbatim.
- Any heading that prefix-matches `compact.preserve_sections`.
- Any fenced code block when `preserve_code_blocks` is true (default).
- The contents of `contracts/*` schema files (OpenAPI, JSON Schema, GraphQL
  SDL). You may strip surrounding markdown prose but the schema bytes must
  be identical.
- The Constitution check matrix in plan.md.
- The acceptance test expectations in tasks.md.
- File path references (anything that looks like a path: `src/...`,
  `./...`, `/...`).

If at any point you are uncertain whether a transformation is lossless, do
**not** apply it. Compaction must never invent, summarize away, or merge
distinct requirements.

### Step 6 — Re-anchor headings
After stripping, ensure heading levels are still contiguous (no jump from
`#` to `###`). Promote orphan subheadings as needed. The artifact must
still parse as a valid spec-kit document of its kind.

### Step 7 — Stamp
Append a single line at the very bottom of the compacted file:

```
<!-- token-budget: compacted (level=<level>) on <ISO-8601-date>; original at <basename>.full.md -->
```

This marker lets `usage` and re-runs detect already-compacted files and
skip no-op work.

## Output

For each artifact processed, run the helper script to get character/token
counts before and after, then report:

```
spec.md           4,820 → 2,310 tokens   (-52.1%)   [backup: spec.full.md]
plan.md           6,140 → 3,580 tokens   (-41.7%)   [backup: plan.full.md]
research.md       3,200 → 1,180 tokens   (-63.1%)   [backup: research.full.md]
─────────────────────────────────────────────────
total            14,160 → 7,070 tokens   (-50.1%)
```

Then end the response. Do not narrate the steps you took — the file diff
is the deliverable.

## Scripts

The helper script `.specify/scripts/bash/compact_helper.sh` provides:
- `snapshot <file>` — prints the current token count.
- `backup_if_needed <file>` — copies to `.full.md` if no backup exists yet.
- `summarize <before_path> <after_path>` — prints the one-line report row.
- `has_marker <file>` — exit 0 if file is already compacted.
- `stamp <file> <level>` — append the compaction marker.

Use it to keep your edits auditable and the output consistent. You do the
content rewriting; the script does the bookkeeping.

## Re-running

If an artifact already carries the `<!-- token-budget: compacted -->`
marker, re-compaction works against the `.full.md` backup, **not** the
current compacted version. This prevents lossy compounding across runs.