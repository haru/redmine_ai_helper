# CRF-074: DocumentationAgent#backstory returned the PromptTemplate object instead of its text

**Date**: 2026-10-21
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, types, simplify)
**Feature**: branch `081-fix-prompt-template-validation`
**Files**: lib/redmine_ai_helper/agents/documentation_agent.rb, test/unit/agents/documentation_agent_test.rb, test/unit/prompt_template_callers_test.rb
**Category**: edge-case
**Related**: CRF-069

## Feedback

code review: `load_prompt("documentation_agent/backstory")` was returned without `.format`, so `#<RedmineAiHelper::Util::PromptTemplate:0x...>` reached the LLM system prompt and the leader's agent list. The existing test stubbed `load_prompt` and asserted that the stub came back, pinning the bug.

## Original Code

```ruby
def backstory
  load_prompt("documentation_agent/backstory")
end
```

## Fix

Added `.format`; replaced the test with ones that use the real template and assert a String; a callers test now checks the backstory of every agent in en and ja.

## Root Cause

The 081 audit of `PromptTemplate#format` callers started from `.format` call sites, so a caller that never calls `format` was invisible. A mocked `load_prompt` in the test hid it.

## Prevention

When auditing callers of a loader, grep the loader (`load_prompt`/`load_template`) as well as the method being tightened, and confirm each result is formatted. Do not write a test whose expectation is the value returned by a stub of the code under test.

**Promoted to**: Not yet
