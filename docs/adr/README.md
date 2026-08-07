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
| [005](./005-write-tool-classification-for-read-only-mode.md) | Write-tool classification via a `define_function` DSL attribute for read-only mode | Proposed |
| [006](./006-chat-channel-gateway-architecture.md) | External chat tool gateway with Socket Mode and a serialized worker | Accepted |
| [007](./007-discord-adapter-connection-design.md) | Discord adapter connection design | Accepted (intent choice in decision 1 superseded by ADR-009) |
| [008](./008-chat-channel-context-import.md) | Chat channel conversation context import | Accepted (decision 7 superseded by ADR-009) |
| [009](./009-discord-message-content-intent-required.md) | Require the Discord MESSAGE_CONTENT intent in Identify | Accepted |
| [010](./010-chat-channel-issue-link-rendering.md) | Render issue references as links on the shared gateway send path | Accepted |
| [011](./011-reset-i18n-locale-between-tests.md) | Reset `I18n.locale` before every test | Accepted |
| [012](./012-slack-only-scope-for-websocket-transport-fixes.md) | Scope the WebSocket transport fixes to the Slack adapter, leaving the same latent defects in Discord | Accepted (scope decision superseded by ADR-014) |
| [013](./013-slack-receive-inactivity-liveness-detection.md) | Replace Slack's self-initiated ping/pong-count liveness check with receive-inactivity monitoring | Accepted |
| [014](./014-shared-websocket-transport-in-base-adapter.md) | Move the shared WebSocket transport handling into `BaseAdapter` and apply it to Discord | Accepted |
| [015](./015-agent-write-capability-routing.md) | Guard write-capable steps with an internal capability check that is never exposed to the router | Proposed |
