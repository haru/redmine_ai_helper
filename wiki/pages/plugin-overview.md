---
title: Plugin Overview
type: concept
sources: [S002, S003, S005, S013, S014]
updated: 2026-08-01
---

# Plugin Overview

Redmine AI Helper adds an AI chat sidebar and AI-assisted features to Redmine
(≥ 6.0), backed by a [multi-agent architecture](./multi-agent-architecture.md)
over RubyLLM (S002, S005). This page is the hub linking the wiki's topic pages.

## What it does

- **[Chat sidebar](./chat-sidebar.md)** for questions, explanations, and
  project-related tasks (S002, S013).
- **[Issue AI features](./issue-ai-features.md)** — summarization, comment-draft
  generation, subtask generation, inline description/wiki completion (accept with
  TAB), typo checking, assignee suggestion, and to-do suggestions (S002, S014).
- **[Custom Commands](./custom-commands.md)** — reusable `/command` prompt
  shortcuts (S002).
- **[Project Health Report](./health-report.md)** with history and a REST API
  (S002).
- **[Chat Channel Gateway](./chat-channel-gateway-architecture.md)** — interact
  from external chat tools like Slack/Discord (S002).
- **[Multi-modal File Support](./multi-modal-file-support.md)** — analyze image,
  document, code, and audio attachments (S002).
- **[MCP Integration](./mcp-integration.md)** — both consume external MCP
  servers and expose Redmine itself as one (S002).
- **[Vector Search](./vector-search.md)** via Qdrant — powers similar-issue and
  duplicate-issue detection (S002).

## Configuration essentials

- **Model profiles**: configured on the AI Helper admin settings page; each has
  type (OpenAI/Anthropic/etc. — OpenAI or Anthropic strongly recommended),
  name, access key, model name, temperature (S002).
- **[Think model](./think-model.md)** (optional): a separate model profile for
  deeper-reasoning tasks such as health-report generation and issue-reply
  drafting; when unset, all tasks use the standard profile (S002, S003).
- **Enablement**: AI Helper is a per-project module (Modules tab) gated by role
  permissions such as `view_ai_helper` (S002).
- **Deployment note**: behind Nginx, SSE streaming needs specific proxy
  settings — see [Nginx SSE Proxy](./nginx-sse-proxy.md) (S002).

## Caveat

AI responses may not be fully accurate; users should verify AI-provided
information at their own discretion (S002).
