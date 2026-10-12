# ADR-052: Web search through a dedicated agent, with sources carried on the agent instances

**Date**: 2026-10-12
**Status**: Proposed

## Context

RubyLLM 2.1 provides `Chat#with_provider_tools(:web_search)` for OpenAI (Responses), Anthropic and Gemini, and returns the sources as `Message#citations`. The chat should be able to answer from the web and show the sources, while every other LLM call (issue summaries, completion, goal and step generation, the leader's final answer) must never send a search request, and unsupported providers (Azure OpenAI, OpenAI-compatible) must never receive a web search tool.

## Decision

- Add `RedmineAiHelper::Agents::WebSearchAgent`. It has no tools for Redmine data and is the only code that calls `with_provider_tools`. It is listed for the leader only when `AiHelperSetting.web_search_enabled?` and the main provider's `supports_web_search?` (`LlmProvider.web_search_supported?`: OpenAI, Anthropic, Gemini; an unknown type raises `ArgumentError`. The check is by LLM type only: OpenAI models that RubyLLM routes to Chat Completions (search-preview, audio, realtime) have no web search tool and fail at request time) are both true, through the existing `enabled?` mechanism of `AgentList#list_agents`.
- `WebSearchAgent#perform_task` sends only the content of the last task, so no Redmine data from other steps reaches the search request. For `use_think_model` steps support is decided by the Think provider; an unsupported Think provider answers without searching. Provider errors and answers the provider cut off (`max_tokens`, `content_filter`, `pause_turn`) become error responses; there is no retry and no repeat without web search. Errors in the plugin's own code propagate.
- The leader's system prompt gets a notice when the agent is unavailable, so it tells users that web search cannot be used instead of inventing sources.
- Sources travel as `WebCitation(url, title)` value objects: `WebSearchAgent#citations` → `ChatRoom#citations` (duplicate URLs removed, first position kept) → `LeaderAgent#citations` → the `AiHelperMessage` returned by `Llm#chat`. Return types of the agent methods are unchanged.
- Sources are stored in `ai_helper_messages.citations` (JSON text, NULL when none) and never added to the conversation history sent to the LLM. The screen renders them from an ERB partial (escaped, only `http(s)` URLs become links, `rel="noopener noreferrer"`); the gateway appends them as plain text after the issue-link conversion.
- The switch is one system-wide column, `ai_helper_settings.web_search_enabled` (default false); there is no per-project setting.

## Consequences

- Positive: web search can be added or removed in one place; the other call sites cannot send a search request by construction.
- Positive: no change to SSE, JavaScript or the agents' return types.
- Negative: the leader must decide to route to the agent, so a user's wish to search is honoured only when the leader plans it.
- Negative: the search terms are chosen by the model; the prompt asks it to avoid personal and internal names but this is not enforced.
- Negative: sources are available only after the answer is complete (shown on reload, not streamed).

## Alternatives Considered

- Enable the search tool on the leader's own chat: every leader call, including the goal/step generation and final answer, would carry the tool.
- A BaseAgent-level option or a provider-level flag in `create_chat`: spreads the decision over many call sites and weakens the guarantee that only one agent searches.
- A separate sources table: the sources belong to exactly one answer and are always read with it.
- Carrying sources in `ToolResponse` or the final answer text: changes shared return types and would put sources into the LLM history.
