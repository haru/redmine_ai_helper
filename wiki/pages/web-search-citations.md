---
title: Web Search & Citations
type: decision
sources: [S044]
updated: 2026-10-12
---

# Web Search & Citations

Feature 071 / ADR-052 lets the chat answer from the web and show the sources,
without any other LLM call ever sending a search request (S044).

## Provider mechanism

- Uses RubyLLM 2.1's public `Chat#with_provider_tools(:web_search)`; RubyLLM
  maps it per provider (OpenAI Responses `web_search`, Anthropic
  `web_search_20260318`, Gemini `google_search`) and normalizes sources to
  `Message#citations` (`RubyLLM::Citation`) (S044).
- `Chat#with_citations` is for file attachments, not web search — not used (S044).
- Anthropic `pause_turn` continuations are merged by RubyLLM. Gemini repeats the
  same URL once per supported span, hence de-duplication (S044).
- `BaseProvider#create_chat` is unchanged: Azure and OpenAI-compatible override
  it, and only one agent searches, so the flag lives in that agent (S044).

## One dedicated agent

- `WebSearchAgent` (auto-registered, no Redmine tools) is the only caller of
  `with_provider_tools`. It is listed for the leader only when
  `AiHelperSetting.web_search_enabled?` and the main profile supports search (S044).
- Support is decided by LLM type alone in `LlmProvider.web_search_supported?`
  (OpenAI, Anthropic, Gemini). Azure (may use Chat Completions, which RubyLLM
  rejects) and OpenAI-compatible (endpoint may lack search) are unsupported;
  model metadata is not used, so a wrong entry cannot silently disable search (S044).
- `perform_task` sends only the last task's text as a fresh chat, not the shared
  room history, so issue text read by other agents cannot become search terms.
  Think-model steps use the Think provider's support; if unsupported the step is
  asked without search. Errors are logged and returned as error responses — no
  retry, no search-less repeat (S044).
- Rejected: enabling search on the leader's own call (forbidden by FR-003a), a
  `BaseTools` search function (loses structured sources), overriding
  `add_message` (recipient is only a string) (S044).
- When the agent is unavailable the leader's system prompt gets
  `web_search_unavailable_notice`, so it says search is unavailable instead of
  inventing sources; the notice sits in the stable prefix, compatible with
  [prompt caching](./prompt-caching.md) (S044).

## Sources as value objects

- `WebCitation(url, title)` validates in `initialize` (`ArgumentError`),
  de-duplicates by exact URL keeping first position, and only `http(s)` URLs are
  `linkable?`; others are shown as text, not dropped (S044).
- Path: `WebSearchAgent#citations` → `ChatRoom#citations` →
  `LeaderAgent#citations` → `Llm#chat`'s `AiHelperMessage`. Return types are
  unchanged; an exception answer carries no sources (S044).
- Stored in `ai_helper_messages.citations` (text JSON; `json` types differ
  across DBs; NULL when none) and never added to the LLM history, so the model
  cannot imitate the list (S044).

## Display and setting

- Screen: ERB partial, escaped, shown after the streamed answer by the existing
  reload — see [AI Chat Sidebar](./chat-sidebar.md). Gateway: plain text added
  after issue-link conversion — see
  [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md) (S044).
- One system-wide `web_search_enabled` column (default false); no per-project
  setting. The settings page warns when the main profile is unsupported (S044).

## Related

[Multi-Agent Architecture](./multi-agent-architecture.md) ·
[LLM Provider Layer](./llm-provider-layer.md) ·
[Plugin Overview](./plugin-overview.md)
