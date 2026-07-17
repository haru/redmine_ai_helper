# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the Redmine AI Helper plugin.

## What is an ADR?

An ADR documents a significant architectural decision: what was decided, why, and what alternatives were considered.

## When to write an ADR

Write an ADR when you:
- Introduce a new architectural pattern or component boundary
- Choose a key library or external service
- Make a non-obvious trade-off that future maintainers might question
- Deliberately deviate from framework defaults or project conventions

When unsure, ask the user before proceeding.

## Rules

- **Append-only**: never modify or delete past ADRs. Add a new ADR to supersede an old one.
- **English only**: all ADR content must be written in English.
- **Numbered sequentially**: use the format `NNN-short-title.md` (e.g., `001-use-ruby-llm.md`).

## Template

Copy the template below for each new ADR:

```markdown
# ADR-NNN: Title

**Date**: YYYY-MM-DD
**Status**: Proposed | Accepted | Superseded by ADR-NNN

## Context

Describe the problem or situation that requires a decision.

## Decision

State the decision clearly.

## Consequences

List the positive and negative consequences of this decision.

## Alternatives Considered

Briefly describe alternatives that were rejected and why.
```

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [001](./001-qdrant-payload-index-strategy.md) | Auto-create Qdrant payload indexes for filtered fields | Proposed |
| [002](./002-vector-scope-by-ai-helper-module.md) | Scope vector data registration to projects with ai_helper module enabled | Proposed |
| [003](./003-vector-target-project-selection.md) | Select which projects are registered in the vector database | Proposed |
| [004](./004-structured-output-native-and-fallback.md) | Two-tier structured output — native API schema enforcement with a prompt-based fallback pipeline | Proposed |
