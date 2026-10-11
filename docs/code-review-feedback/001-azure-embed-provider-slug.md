# CRF-001: Azure embedding still used the :openai provider after the :azure migration

**Date**: 2026-10-11
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `feature/069-ruby-llm-2-1-migration`
**Files**: lib/redmine_ai_helper/llm_client/base_provider.rb, azure_open_ai_provider.rb, test/unit/llm_client/azure_open_ai_provider_test.rb
**Category**: edge-case
**Related**: None

## Feedback

`BaseProvider#embed` forced `provider: :openai` for Azure, but `build_context` now sets only `azure_*` keys, so Azure embeddings (vector search, embedding connection test) raised `ConfigurationError: OpenAI provider is not configured`.

## Original Code

```ruby
opts[:provider] = :openai if ruby_llm_provider_class.nil?
```

## Fix

Added an overridable `embedding_provider_slug` (`:openai` by default, `:azure` in `AzureOpenAiProvider`) and a test asserting `embed` uses `provider: :azure`.

## Root Cause

The AI changed the Azure provider's `create_chat` and `build_context` as the spec/research (R3, T009) described, but never searched for other code that relied on the old assumption that Azure is configured through `openai_*` keys. The spec and tests covered only `create_chat`, so nothing failed.

## Prevention

When a provider's configuration keys or slug change, grep every method of the provider hierarchy that selects a provider by slug (`embed`, `create_chat`, model registration) and add a test per entry point (chat, embed, model fetch), not only the one named in the spec.

**Promoted to**: Not yet
