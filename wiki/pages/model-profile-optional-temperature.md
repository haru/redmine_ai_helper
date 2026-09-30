---
title: Model Profile Temperature Is Optional
type: decision
sources: [S037]
updated: 2026-09-30
---

# Model Profile Temperature Is Optional

Issue #465 ("temperature is deprecated") led to making a model profile's
`temperature` optional (feature 062, ADR-042). When it is blank, the plugin
sends **no** temperature and lets the AI service use its own default (S037).

## Why nothing changes in the client layer

`BaseProvider#create_chat`, `OpenAiCompatibleProvider#create_chat` and
`AzureOpenAiProvider#create_chat` already do
`chat.with_temperature(temperature) if temperature`; Anthropic, Gemini and
OpenAI use the base method. A `nil` temperature therefore drops out of every
path (chat, summary, suggestions, file analysis, think, vector) (S037). See
[LLM Provider Layer](./llm-provider-layer.md).

## What changed

- **Validation**: `presence: true` removed; `numericality >= 0.0` now uses
  `allow_nil: true`. Rails' `Float` type casts `""` and whitespace-only input
  to `nil`, so blank passes, while `"abc"` still fails (numericality reads the
  pre-cast value) and `0` stays `0.0`, distinct from `nil` (S037).
- **Column default**: a new migration drops the `0.5` column default with
  `change_column_default ... from: 0.5, to: nil`; existing rows keep their
  values and new profiles start with an empty field (S037).
- **Connection test**: the implicit `temperature ||= 1.0` in
  `AiHelperModelProfilesController#test_connection` was deleted (S037).
- **Form**: `required: true` removed from the field; show view, `copy`
  (`dup`) and Langfuse tracing already tolerate `nil` (S037).

## Kept as-is

`handle_gpt5_temperature` (a `before_validation`) still forces 1.0 for GPT-5
family models on save, even from blank (S037).

## Alternatives rejected

- Per-provider/model capability detection: out of scope, YAGNI (S037).
- Setting `temperature = nil` in the controller's `new`: leaves 0.5 for
  profiles created from code/console, contradicting "the plugin fills in no
  value" (S037).
- Editing the old migration: never reaches already-migrated installs (S037).
- `allow_blank` / explicit `before_validation` blanking: redundant with type
  casting (S037).

## Related

[LLM Provider Layer](./llm-provider-layer.md) · [Think Model](./think-model.md)
