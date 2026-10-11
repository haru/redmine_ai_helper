# Specification Feedback Log

This directory records corrections the user requested on AI-written specifications, together with an analysis of why the AI produced the original text.

## Purpose

AI-generated specifications often miss the author's intent and need correction. Each correction is recorded here so that the same kind of mistake is not repeated. Before writing or updating a specification, read the index below and the entries relevant to the feature.

## When to record

Record an entry when the user asks to correct an AI-written specification artifact and the correction is applied:

- `specs/` feature artifacts (`spec.md`, `plan.md`, `tasks.md`, `research.md`, `data-model.md`, contracts, etc.)
- Design documents written for a feature

Do **not** record:

- Typo fixes or pure wording changes that do not change meaning
- Changes the user makes for reasons unrelated to the AI output (e.g. the user changed requirements that were captured correctly)

When one correction request contains several points, combine the points that share a root cause into one entry and split points with different root causes into separate entries.

## Rules

- **Append-only**: never modify or delete past entries. If an entry turns out to be wrong, add a new entry that references and corrects it. The only edits allowed on existing files are adding rows to this README's index and, when an entry's prevention rule is promoted, updating that entry's **Promoted to** field and the matching index cell.
- **English only**: all entries must be written in English, even when the conversation was in another language. Quote the user's feedback as a faithful English translation.
- **Numbered sequentially**: use the format `NNN-short-title.md` (e.g., `001-assumed-default-permission.md`). If another branch merged an entry with the same number first, renumber yours (file name, heading, and index row) before merging.
- Use the `record-spec-feedback` skill to create entries.

## Root-cause categories

| Category | Meaning |
|----------|---------|
| `missing-context` | Information needed to write it correctly was not available to the AI (not in the request, specs, wiki, or code) |
| `unconfirmed-assumption` | The AI filled an ambiguous point with a guess instead of asking |
| `intent-misread` | The request was clear, but the AI interpreted it differently |
| `scope-creep` | The AI added requirements, behavior, or work that was not requested |
| `scope-gap` | The AI omitted something that was requested or clearly implied |
| `convention-unknown` | The AI did not follow an existing specification, behavior, or project convention it could have found |
| `granularity` | The level of detail was wrong (too detailed, too abstract, implementation details in the spec, etc.) |
| `other` | None of the above; explain in the entry and consider adding a new category |

Add a new category to this table when a recurring cause does not fit the existing ones.

## Template

```markdown
# SF-NNN: Title

**Date**: YYYY-MM-DD
**Feature**: specs/NNN-feature-name (branch `feature/NNN-...`)
**Artifact**: spec.md | plan.md | tasks.md | <other file>
**Category**: <category from the table>
**Related**: SF-NNN, ... (entries with the same pattern; "None" if none)

## Feedback

What the user pointed out (faithful English summary or translated quote).

## What the AI Wrote

The relevant part of the original output (excerpt or summary).

## Correction

How the artifact was changed.

## Root Cause

Why the AI produced the original text: what it relied on, what it should have
checked or asked, and why it did not.

## Prevention

A concrete, checkable rule to apply when writing future specifications.

**Promoted to**: AGENTS.md | constitution | <skill> | Not yet
```

## Index

| Entry | Title | Category | Feature | Promoted to |
|-------|-------|----------|---------|-------------|
