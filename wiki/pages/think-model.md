---
title: Think Model
type: component
sources: [S003]
updated: 2026-08-01
---

# Think Model

An **optional** second model profile for tasks that need deeper analysis, used
in addition to the normal model (S003). When unset, every task uses the normal
model, so upgrading existing installs changes nothing (S003).

## Where it applies

Think model is used automatically for (S003):

- **Project health report** generation **and comparison** (FR-007/008).
- **Issue-screen reply drafting** (FR-009).

It is **not** used for the sidebar chat — even a reply-draft requested from the
sidebar uses the normal model (FR-010, SC-005) (S003). The split works because
those code paths enter through different entry points than the sidebar chat and
the task type is distinguishable (S003). See
[BaseAgent LLM Calls](./base-agent-llm-calls.md) for the mechanism.

## Configuration

Stored on the global `AiHelperSetting`: `use_think_model` (flag) and
`think_model_profile_id` (an [AiHelperModelProfile] reference) (S003). The
settings UI places the "Use think model" checkbox **between** the normal-model
and vector-search-model settings; the model picker shows only when checked
(S003). The think model **may use a different provider** than the normal model
(e.g. normal = OpenAI, think = Anthropic) (S003).

## Rules and edge cases

- **Validation**: saving with `use_think_model = true` but no profile selected is
  rejected with a validation error — the contradictory
  `use_think_model=true, think_model_profile_id=nil` state is never persisted (S003).
- **No silent fallback**: if the think profile is later deleted/disabled, or its
  API key is invalid/expired, the error is surfaced through the *same* error
  flow as normal-model errors — it does **not** silently fall back to the normal
  model (S003).
- Selecting the *same* profile as the normal model works fine (S003).
- With zero model profiles, checking the box shows an empty selection rather
  than failing (S003).
- **Langfuse**: think-model calls are not tagged distinctly; they are identified
  naturally by the model name recorded in the trace (S003).

## Out of scope

Per-project think-model settings, and having `LeaderAgent` dynamically pick the
think model per task, are explicitly out of scope; `@think_llm_provider` /
`think_chat` are the foundation a future version would build that on (S003).

## Related

- [BaseAgent LLM Calls](./base-agent-llm-calls.md)
- [Project Health Report](./health-report.md) · [Plugin Overview](./plugin-overview.md)
