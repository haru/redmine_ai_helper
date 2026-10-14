# SF-001: Assumed Azure OpenAI keeps Chat Completions without asking

**Date**: 2026-10-11
**Feature**: specs/069-ruby-llm-2-1-migration (branch `feature/069-ruby-llm-2-1-migration`)
**Artifact**: spec.md
**Category**: unconfirmed-assumption
**Related**: None

## Feedback

During `/speckit-clarify`, the user was asked which API the Azure OpenAI provider should use after the RubyLLM 2.1 migration (keep Chat Completions / switch to the Responses API / follow RubyLLM 2.1's Azure provider default). The user chose: "Check the default of RubyLLM 2.1's Azure provider during planning and follow it." This overturned what the AI had already written in the spec.

## What the AI Wrote

- FR-015: "The Azure OpenAI provider MUST keep working with the same settings as before the migration."
- Assumptions: "Azure OpenAI communicates through the same Chat Completions API as before the migration. Switching to the Responses API is out of scope."

## Correction

- FR-015 now says the plugin does not choose the API for Azure OpenAI and follows the default of RubyLLM 2.1's Azure provider; the default is confirmed during planning and recorded in plan.md. Existing Azure profiles must still work with the same settings.
- The Assumptions bullet was replaced with "The Azure OpenAI API follows RubyLLM 2.1's default (FR-015). No setting for choosing the API is added to Azure profiles."
- The Azure edge case was updated to reference FR-006 and FR-015.

## Root Cause

The research notes (`tmp/ruby_llm_2.1_migration_research.md`) only flagged the Responses API default as a risk for OpenAI-compatible servers and did not state what RubyLLM 2.1 does for Azure. The AI filled that gap by choosing the most conservative option ("keep the current behavior") and wrote it as a settled assumption instead of marking it as open. It did not notice that the choice also decided whether Issue #480 (the feature's main motivation) would be fixed for Azure users, which made it a scope decision the user needed to make. The AI had already spent its single [NEEDS CLARIFICATION] marker on SSE and treated the remaining open points as safe defaults.

## Prevention

When a library migration changes a default behavior (e.g. an API protocol) and the research does not say how that change applies to each affected provider or component, do not write a "keep current behavior" assumption for the unverified ones. List each unverified case as an open decision (a [NEEDS CLARIFICATION] marker or an explicit "to be confirmed during planning" requirement) and state whether the choice affects the feature's main goal.

**Promoted to**: Not yet
