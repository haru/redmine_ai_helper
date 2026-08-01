---
title: AI Chat Sidebar
type: component
sources: [S013]
updated: 2026-08-01
---

# AI Chat Sidebar

The chat UI injected into Redmine's right side: it gathers page context, streams
answers, and renders them safely (S013). This is the frontend to the
[Multi-Agent Architecture](./multi-agent-architecture.md).

> Provenance: DeepWiki auto-generated doc (S013); several names corroborate
> other pages (`messages_for_openai`, `CustomCommandExpander`,
> `AiHelperMarkdownParser`, `ActionController::Live`).

## View injection & page context

The sidebar is added through Redmine **view hooks**; the `_sidebar.html.erb`
partial detects the current controller and pulls the object context — issue ID,
wiki page ID, repository ID — into `ai_helper.page_info` so answers are
context-aware (S013). Every request carries this page metadata, which the backend
`LeaderAgent` uses to ground its response (S013).

## Frontend (`AiHelper` JS class)

A single `AiHelper` JavaScript class runs the UI lifecycle (S013):

- Collapsed/expanded state persists in `localStorage`
  (`aihelper-fold-flag_${userId}`) across sessions (S013).
- `submitAction` populates hidden fields — `ai_helper_controller_name`,
  `ai_helper_action_name`, `ai_helper_content_id` — carrying the page context on
  submit (S013).
- **Read-only cue**: the sidebar title shows a **"(Read-only)"** suffix when the
  plugin is in read-only mode (S013).

## Streaming

The request goes out over XHR; the backend streams via `ActionController::Live`
+ SSE (see [Nginx SSE Proxy](./nginx-sse-proxy.md)). On the client,
`handleSSEStream` reads chunks in `xhr.onprogress`, parsing newline-delimited
JSON events, and watches for `event: interactive_options` to render choice
buttons (S013).

## Conversation persistence

`AiHelperConversation` (belongs to a user; holds the thread) and
`AiHelperMessage` (individual messages with `user`/`assistant` roles) store the
chat; `messages_for_openai` converts records to the LLM's `role`/`content`
format (S013) — the same method that folds in imported
[context messages](./chat-context-import.md).

## Commands, Markdown & XSS

- `/command` autocomplete is provided by the `AiHelperCommandCompletion`
  dropdown; the backend `CustomCommandExpander` substitutes `{input}`,
  `{user_name}`, `{project_name}` before the LLM sees the prompt (S013). See
  [Custom Commands](./custom-commands.md).
- `AiHelperMarkdownParser` renders headers, lists, tables, code blocks, and
  **linkifies `#NNN`** into clickable Redmine issue links; its `sanitizeOutput`
  strips dangerous tags and event handlers to prevent **XSS** (S013). The same
  parser renders [health reports](./health-report.md) client-side.

## Related

- [Multi-Agent Architecture](./multi-agent-architecture.md) ·
  [Custom Commands](./custom-commands.md) ·
  [Chat Context Import](./chat-context-import.md) ·
  [Plugin Overview](./plugin-overview.md)
