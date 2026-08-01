---
title: Custom Commands
type: component
sources: [S002]
updated: 2026-08-01
---

# Custom Commands

Reusable prompt shortcuts for the AI Helper chat. Define a command once, invoke
it by typing `/commandname` in the chat input; an autocomplete dropdown lists
available commands with descriptions (S002). Managed from the "Custom Commands"
tab on the AI Helper dashboard (S002).

## Scope and precedence

Three scope levels exist, resolved by this precedence when names collide (S002):

1. **User** (personal, visible only to you) — highest priority
2. **Project** (within a specific project)
3. **Global** (across all projects) — lowest priority

## Template variables

Commands expand these variables for dynamic prompts: `{input}`, `{user_name}`,
`{project_name}`, `{datetime}` (S002). Expansion is handled by
`CustomCommandExpander` over `/command_name input` syntax; definitions are
stored in `AiHelperCustomCommand`.

## Related

- [Plugin Overview](./plugin-overview.md)
