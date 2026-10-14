# CRF-009: Instructions value object and apply_instructions accepted invalid input silently

**Date**: 2026-10-11
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `feature/070-prompt-caching`
**Files**: lib/redmine_ai_helper/llm_client/instructions.rb, base_provider.rb, anthropic_provider.rb, app/models/ai_helper_model_profile.rb, test/unit/llm_client/instructions_test.rb
**Category**: error-handling
**Related**: CRF-003

## Feedback

The error-handling and type-design reviewers found that `Instructions.new(fixed: nil, variable: "")` was valid: the base provider then called `with_instructions(nil)` (RubyLLM removes all system messages) and Anthropic sent only the variable part, silently dropping the role, backstory and read-only notice. `apply_instructions` also turned any truthy object (Hash, template object) into a system prompt via `to_s` without raising, and the base class and Anthropic handled the String/Instructions/nil union differently.

## Original Code

```ruby
Instructions = Data.define(:fixed, :variable) do
  def to_s
    variable.to_s.empty? ? fixed : "#{fixed}\n\n#{variable}"
  end
end

def apply_instructions(chat, instructions)
  chat.with_instructions(instructions.to_s) if instructions
end
```

## Fix

`Instructions#initialize` raises `ArgumentError` unless `fixed` is a non-empty String and `variable` is a String (`variable` defaults to `""`). Added `Instructions.coerce` (nil → nil, String → wrapped, Instructions → itself, anything else → `ArgumentError`) and a `variable?` predicate. Both `apply_instructions` implementations coerce first, so the Anthropic override is a single path. Added `AiHelperModelProfile#prompt_caching_active?` and the Anthropic provider raises "Model Profile not found" itself instead of relying on `model_name` having raised first.

## Root Cause

The AI used `Data.define` for immutability and treated the YARD `@param [String, Instructions, nil]` as the contract, without enforcing it. The "never implement fallback error handling" rule in AGENTS.md was applied to `rescue` blocks only; duck-typed `to_s` and `.to_s.empty?` on possibly-nil values are fallbacks of the same kind.

## Prevention

A new value object must validate its documented invariants in `initialize` and raise `ArgumentError`. A method documented to accept a type union must branch on the types explicitly and raise on anything else; do not rely on `to_s` or `&.` to accept unexpected values.

**Promoted to**: AGENTS.md
