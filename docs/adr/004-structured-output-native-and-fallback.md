# ADR-004: Two-tier structured output — native API schema enforcement with a prompt-based fallback pipeline

**Date**: 2026-07-17
**Status**: Proposed

## Context

Six call sites in the plugin request structured JSON from the LLM (sub-issue draft generation, assignee suggestion, leader goal/step generation, documentation suggestions, and issue content analysis for vector search). Historically they all relied on prompt-embedded format instructions plus `JSON.parse`, which crashed when the model deviated from the requested schema — for example returning a bare JSON array instead of the declared wrapper object, or inventing undeclared keys (issue #345, `undefined method 'each' for nil` during sub-issue draft generation).

ruby_llm 1.16.0 provides `RubyLLM::Chat#with_schema` for API-level structured output (OpenAI `response_format`, Gemini `responseSchema`, etc.) and `RubyLLM::Model::Info#structured_output?` to detect model capability from its registry. However, not every configured provider supports this: Azure OpenAI and OpenAI-compatible endpoints have no registry slug in our provider layer, and locally hosted models may not be registered at all.

## Decision

1. **Two-tier architecture.** `BaseAgent#structured_chat` checks `LlmClient::BaseProvider#supports_structured_output?`:
   - **Native tier**: the JSON schema is passed to `create_chat(schema:)`, which applies `chat.with_schema`. Prompt-embedded format instructions are omitted (`format_instructions_for` returns `""`).
   - **Fallback tier**: the existing prompt-instruction approach (`get_format_instructions`) is kept, and the textual response goes through JSON extraction/parsing with at most one LLM parse-fix retry.
2. **Capability detection is conservative.** `supports_structured_output?` returns `false` when the provider has no `ruby_llm_provider_slug` (Azure OpenAI, OpenAI-compatible) or the model is not in the RubyLLM registry. Unknown means fallback, never native.
3. **Both tiers converge into one deterministic pipeline** in `StructuredOutputHelper.parse`: conform (wrap a bare array into the single array-type property; recursively strip undeclared keys) → validate (`required` presence and `type` checks only, no coercion) → on violations, at most one schema-regeneration request → if still violating, raise `SchemaViolationError` after logging the original response and violation list. There is no silent fallback to partial data.
4. **`strict: false` for native schemas.** `StructuredOutputHelper.native_schema_payload` always emits `{ name:, schema:, strict: false }` and passes the existing schemas through unchanged.

## Consequences

**Positive**:
- Schema deviations no longer crash user-facing features; the deterministic conform/validate steps absorb the common deviations from issue #345 at zero LLM cost.
- On native-capable models the happy path needs no extra LLM calls and no format-instruction tokens in the prompt.
- A single pipeline behind both tiers keeps the test surface small and behavior uniform across all six call sites.
- Unresolvable deviations fail loudly (`SchemaViolationError` with logged evidence), preserving the project's no-silent-fallback principle.

**Negative**:
- `strict: false` means the API does not hard-guarantee schema conformance even on the native tier; residual deviations rely on the conform/validate pipeline.
- The fallback tier can add up to two extra LLM calls in the worst case (one parse fix + one schema regeneration).
- Capability detection depends on the RubyLLM model registry; a capable but unregistered model silently uses the fallback tier (correct but less efficient).

## Alternatives Considered

- **`strict: true` with automatic schema transformation**: OpenAI strict mode requires `additionalProperties: false` everywhere and every property listed in `required` (optional fields become null-unions). Converting the existing schemas (which have genuinely optional fields such as `priority_id` and `due_date`) would need forward transformation plus null-stripping on responses, changing the meaning of six schema definitions. Rejected as disproportionate complexity (YAGNI); can be revisited in a future ADR.
- **Full JSON Schema validation via a gem (json_schemer / json-schema)**: adds a dependency, and its error output would still need custom mapping into regeneration prompts. `required` + `type` checking is sufficient as a boundary guard before ActiveRecord mass assignment. Rejected.
- **Model-name pattern matching for capability detection**: fragile, needs maintenance for every new model, and risks false positives that would break requests. Rejected in favor of the RubyLLM registry.
- **Native tier only where available, no conformance pipeline**: would leave fallback providers (and `strict: false` residual deviations) exposed to the original crash class. Rejected.
