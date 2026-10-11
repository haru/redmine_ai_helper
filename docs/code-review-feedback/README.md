# Code Review Feedback Log

This directory records code review findings on AI-generated code that led to a code change, together with an analysis of why the AI produced the original code.

## Purpose

AI-generated code often receives review findings that require fixes. Each adopted finding is recorded here so that the same kind of mistake is not repeated. Before generating code, read the index below and the entries relevant to the files or area you are about to change.

## When to record

Record an entry when a finding from one of the following reviews leads to a code change:

- GitHub Copilot review on a pull request
- A local AI review (e.g. `/code-review`, `speckit-review-*` skills)

Do **not** record:

- Findings that were not adopted (no code change)
- Typo fixes or pure formatting changes

When one review contains several findings, combine the findings that share a root cause into one entry and split findings with different root causes into separate entries.

## Rules

- **Append-only**: never modify or delete past entries. If an entry turns out to be wrong, add a new entry that references and corrects it. The only edits allowed on existing files are adding rows to this README's index and, when an entry's prevention rule is promoted, updating that entry's **Promoted to** field and the matching index cell.
- **English only**: all entries must be written in English.
- **Numbered sequentially**: use the format `NNN-short-title.md` (e.g., `001-n-plus-one-in-version-list.md`). If another branch merged an entry with the same number first, renumber yours (file name, heading, and index row) before merging.
- Use the `record-code-review-feedback` skill to create entries.

## Root-cause categories

| Category | Meaning |
|----------|---------|
| `convention-violation` | The code broke a rule in AGENTS.md, the constitution, an ADR, or an established project pattern |
| `error-handling` | Wrong error handling (silent fallback, wrong error type, missing handling) |
| `security` | Security issue (XSS, injection, secret exposure, etc.) |
| `permission` | Missing or wrong Redmine permission / visibility check |
| `edge-case` | An input or state the code did not handle (nil, empty, boundary) |
| `performance` | Inefficient code (N+1 queries, unnecessary loading) |
| `test-gap` | Missing, weak, or environment-dependent tests |
| `readability` | Naming, duplication, unnecessary complexity |
| `doc-comment` | Inaccurate or missing comments / YARD docs |
| `other` | None of the above; explain in the entry and consider adding a new category |

Add a new category to this table when a recurring cause does not fit the existing ones.

## Template

```markdown
# CRF-NNN: Title

**Date**: YYYY-MM-DD
**Source**: GitHub Copilot (PR #NNN) | Local AI review (<skill or command>)
**Feature**: branch `feature/NNN-...` / PR #NNN
**Files**: path/to/file.rb, ...
**Category**: <category from the table>
**Related**: CRF-NNN, ... (entries with the same pattern; "None" if none)

## Feedback

What the reviewer pointed out (summary, with a link to the review comment if available).

## Original Code

The relevant excerpt of the code before the fix.

## Fix

How the code was changed (excerpt or summary, commit hash if available).

## Root Cause

Why the AI generated the original code: what it relied on, what it should have
checked, and why it did not.

## Prevention

A concrete, checkable rule to apply when generating future code.

**Promoted to**: AGENTS.md | constitution | ADR-NNN | <skill> | Not yet
```

## Index

| Entry | Title | Category | Source | Promoted to |
|-------|-------|----------|--------|-------------|
