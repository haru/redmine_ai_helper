# CRF-005: Dead branches, stale comments and tests tied to the old API left after the RubyLLM 2.1 migration

**Date**: 2026-10-11
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `feature/069-ruby-llm-2-1-migration`
**Files**: lib/redmine_ai_helper/util/structured_output_helper.rb, base_agent.rb, llm_client/anthropic_provider.rb, gemini_provider.rb, AGENTS.md, .github/copilot-instructions.md, wiki/pages/*.md, test/unit/**
**Category**: doc-comment
**Related**: CRF-003

## Feedback

After migrating, Hash/Array response branches that RubyLLM 2.1 can no longer produce, Hash-stubbed tests, `on_end_message` and SSE/`ruby_llm-mcp` references in docs, and comments claiming the API rejects the `user` field remained.

## Original Code

```ruby
return response if response.is_a?(Hash) || response.is_a?(Array)
```

## Fix

Removed the dead branches and updated YARD, comments, AGENTS.md, copilot instructions, README, ADR-049 and wiki pages; tests now use JSON strings and `RubyLLM::Tokens`.

## Root Cause

The AI made the minimal renames needed to compile and pass tests, editing mocks in the same commit as the code, and did not sweep for behaviour and wording that the new library made obsolete.

## Prevention

After a library migration, grep the repo (code, comments, AGENTS.md, wiki, tests) for every removed API name and for type assumptions the library no longer allows (e.g. Hash content), and delete or update them in the same change.

**Promoted to**: AGENTS.md
