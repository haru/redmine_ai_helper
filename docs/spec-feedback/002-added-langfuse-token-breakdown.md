# SF-002: Added Langfuse token breakdown fields not recorded today

**Date**: 2026-10-11
**Feature**: specs/069-ruby-llm-2-1-migration (branch `feature/069-ruby-llm-2-1-migration`)
**Artifact**: spec.md
**Category**: scope-creep
**Related**: None

## Feedback

During `/speckit-clarify`, the user was asked whether Langfuse should keep recording only the same three token fields as before (input, output, total) or also record the new breakdowns RubyLLM 2.x exposes (cache read, thinking). The user chose: "Record only the same three fields as before the migration."

## What the AI Wrote

FR-016: "When Langfuse integration is enabled, a generation MUST be recorded for each LLM call, as before the migration, with input, output, model name, and token usage (input and output, plus breakdowns such as cache reads when available)."

This contradicted SC-006, which requires the recorded fields to match those recorded before the migration.

## Correction

FR-016 now requires token usage as three fields (input, output, total) and states that the breakdowns newly available in RubyLLM 2.x (cache read, thinking, etc.) are not added.

## Root Cause

The AI based FR-016 on the research notes, which mention that RubyLLM 2.0 renames token fields (`cached` → `cache_read`, `reasoning` → `thinking`). It read the renamed fields as something the plugin records, without checking `BaseAgent#setup_langfuse_callbacks` in `lib/redmine_ai_helper/base_agent.rb`, which only sends `prompt_tokens`, `completion_tokens`, and `total_tokens`. In a migration spec whose goal is "keep existing behavior", it described a new capability of the library as a requirement and did not cross-check the requirement against the success criterion that demands parity.

## Prevention

In a migration or "keep existing behavior" spec, before writing a requirement that lists the fields, options, or outputs of an existing feature, read the code that produces them today and list exactly those. Do not add items only because the new library version makes them available; if they seem useful, ask the user or note them as out of scope. Check that every such requirement agrees with the parity success criteria.

**Promoted to**: Not yet
