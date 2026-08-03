---
title: Tool System
type: component
sources: [S008]
updated: 2026-08-01
---

# Tool System

Agents touch Redmine **only** through tools. Tools are declared with a DSL on
`RedmineAiHelper::BaseTools` and compiled into `RubyLLM::Tool` subclasses the LLM
can call by function-calling (S008). Part of the
[Multi-Agent Architecture](./multi-agent-architecture.md).

> Provenance: structural claims here come from the DeepWiki auto-generated doc
> (S008); the DSL names (`define_function`/`property`/`item`,
> `available_tool_providers`) match the project's own conventions.

## The DSL

- **`define_function`** — declares the tool's name, description, and a
  **`write: true`** flag marking mutating vs. read-only operations (S008).
- **`property`** — an input parameter with type, description, and required flag (S008).
- **`item`** — the element shape of an array/object property (S008).

Tools are grouped into **providers** (each a `BaseTools` subclass); an agent
overrides `available_tool_providers` / `available_tool_classes` to control which
providers' functions it may call — a per-agent permission boundary (S008).

## Security & read-only

- **Read checks**: read tools validate access with `issue.visible?` or
  `accessible_project?` (S008).
- **Write checks**: write tools call `User.current.allowed_to?(:action, project)`
  (S008).
- **Read-only mode**: because each mutating tool is tagged `write: true`, global
  read-only mode can filter those individual tools out (S008). This is why
  *internal* tools can be selectively disabled, whereas external
  [MCP](./mcp-integration.md) agents — whose tools carry no such flag — are
  disabled wholesale.
- **Atomic writes**: `IssueUpdateTools` wraps changes in `Issue.transaction` so
  relations and custom fields persist consistently (S008).
- **`validate_only`**: a parameter that runs schema validation without
  persisting — an LLM pre-check before an actual write (S008).
- **VectorTools dual filtering**: results are filtered first by Qdrant metadata,
  then again post-retrieval by visibility/permission, preventing leakage (S008).
  See [Vector Search](./vector-search.md).

## Tool providers (selection)

| Provider | Purpose |
|---|---|
| `IssueTools`, `IssueSearchTools` | Issue read/search; filter operators like `=`, `>=`, `><t+` |
| `IssueUpdateTools` | Create/update issues (atomic, `parent_issue_id` hierarchy) |
| `ProjectTools`, `VersionTools` | Metadata; `accessible_project?` checks |
| `WikiTools`, `WikiWriteTools` | Wiki read / write |
| `VectorTools` | Semantic search over Qdrant |
| `FileTools` | Document analysis via prompt templates |
| `ImageTools` | Image-attachment handling |
| `UserTools`, `SystemTools`, `BoardTools`, `RepositoryTools` | Users, env info, forums, SCM |

## Gotchas

- LLM-supplied JSON filter keys may arrive as strings; tools **normalize nested
  hash keys** before use (S008).
- `FileTools` reads localized prompt templates (`file_tools/analyze.yml`) (S008).

## Related

- [Multi-Agent Architecture](./multi-agent-architecture.md) ·
  [MCP Integration](./mcp-integration.md) · [Vector Search](./vector-search.md)
