# CRF-112: Wiki completion kept a catch-all rescue next to the narrowed one, on two layers

**Date**: 2026-11-21
**Source**: Local AI review (speckit-review-run, 6 agents)
**Feature**: branch `feature/089-ruby-llm-2-2-upgrade`
**Files**: lib/redmine_ai_helper/agents/wiki_agent.rb, lib/redmine_ai_helper/llm.rb
**Category**: error-handling
**Related**: CRF-003, CRF-014, CRF-022

## Feedback

The errors review flagged `rescue => e` in `WikiAgent#generate_wiki_completion`, left directly below the new `rescue RubyLLM::ConnectionError`: it turned any `StandardError` into an empty completion. Adding an adapter-level test showed that `Llm#generate_wiki_completion` had the same catch-all one layer up, so narrowing only the agent changed nothing for the user.

## Original Code

```ruby
rescue RubyLLM::ConnectionError => e   # WikiAgent
  ...
rescue => e                            # WikiAgent: kept "out of scope" in ADR-074
  ""
...
rescue => e                            # Llm#generate_wiki_completion
  ""
```

## Fix

Both rescues list `RubyLLM::Error` only, matching the issue completion path; the timeout case is chosen with `ConnectionErrorHelper.timeout?`. Defects now reach the controller's HTTP 500. ADR-074 was rewritten to say so.

## Root Cause

The change was scoped to "timeout classification", so the existing catch-all was declared out of scope in the ADR instead of being checked against the AGENTS.md no-fallback rule. The callers of the shared path (`Llm`, then the controller) were not read, so the second catch-all was missed until a test through the controller returned 200.

## Prevention

When a change touches a rescue clause, replace every `rescue => e`/`StandardError` that turns failures into a return value in that method and in each caller up to the controller, or ask the user; never record a catch-all as "out of scope" in an ADR. Verify with a test from the controller that a defect returns 500.

**Promoted to**: Not yet
