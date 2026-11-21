---
title: Tool System
type: component
sources: [S008, S016, S026, S032, S033, S034, S036, S041, S042]
updated: 2026-11-21
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

Permission checks and read-only filtering are on a separate page. See [Tool System Security & Read-Only Mode](./tool-system-security.md) (S008, S016, S026, S033, S034).

## Tool providers (selection)

| Provider | Purpose |
|---|---|
| `IssueTools`, `IssueSearchTools` | Issue read/search; filter operators like `=`, `>=`, `><t+` |
| `IssueUpdateTools` | Create/update issues (atomic, `parent_issue_id` hierarchy) |
| `ProjectTools`, `VersionTools` | Metadata; `accessible_project?` checks |
| `VersionWriteTools` | Version create/update/delete — see [Version Write Tools](./version-write-tools.md) (S041) |
| `WikiTools`, `WikiWriteTools` | Wiki read / write — see [Wiki Tools](./wiki-tools.md) |
| `VectorTools` | Semantic search over Qdrant |
| `FileTools` | Document analysis via prompt templates |
| `ImageTools` | Image-attachment handling |
| `UserTools`, `SystemTools`, `BoardTools`, `RepositoryTools` | Users, env info + admin [log access](./log-file-access-tools.md) (S036), forums, SCM |

## Gotchas

- **Error convention**: most tools `raise` on failure, which in chat aborts the
  whole tool loop. The version tools return `{ error: }` for user mistakes and
  raise only for system failures — see
  [Version Write Tools: Strict Input & Error Results](./version-write-tools-error-policy.md) (S041).

- LLM-supplied JSON filter keys may arrive as strings; tools **normalize nested
  hash keys** before use (S008).
- `FileTools` reads localized prompt templates (`file_tools/analyze.yml`) (S008).

## RubyLLM 2.x DSL rename

`BaseTools.define_function` now calls RubyLLM's `parameters` (formerly `params`) when building tool classes (S042). See [RubyLLM 2.1 Migration](./ruby-llm-2-1-migration.md).

## Related

- [Multi-Agent Architecture](./multi-agent-architecture.md) ·
  [MCP Integration](./mcp-integration.md) · [Vector Search](./vector-search.md)
- [Agent Write-Capability Routing](./agent-write-capability-routing.md)
- [search_issues Cross-Project Scoping](./search-issues-cross-project-scoping.md)
- [Wiki Tools](./wiki-tools.md)
- [Version Write Tools](./version-write-tools.md)
- [Project Management Tools](./project-management-tools.md)
- [All-Projects Data-Access Scope](./all-projects-data-access-scope.md)
