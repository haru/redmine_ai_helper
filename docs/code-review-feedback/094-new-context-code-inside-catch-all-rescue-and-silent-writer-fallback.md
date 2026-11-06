# CRF-094: New completion-context code ran inside a catch-all rescue, and the writer silently fell back to the current user

**Date**: 2026-11-03
**Source**: Local AI review (speckit-review-run: errors, types, code)
**Feature**: branch `feature/085-journal-edit-typo-completion`
**Files**: lib/redmine_ai_helper/agents/issue_read_agent.rb, lib/redmine_ai_helper/llm.rb, lib/redmine_ai_helper/util/completion_journal_resolver.rb, app/controllers/ai_helper_controller.rb, test/unit/agents/issue_read_agent_test.rb, test/unit/llm_test.rb, test/unit/util/completion_journal_resolver_test.rb, test/functional/ai_helper_controller_test.rb
**Category**: error-handling
**Related**: CRF-014, CRF-022, CRF-009

## Feedback

- `build_completion_context` (now with `build_note_specific_context` and
  `select_note_candidates`) ran inside `generate_text_completion`'s
  `rescue => e` → `""`, and `Llm#generate_text_completion` had the same
  rescue. A defect in the new code (for example a `nil` `created_on`) showed
  up as "no suggestion", and the controller's 500 branch was unreachable.
- `writer = journal&.user || User.current` switched the writer to the current
  user when a journal had no user, the identity mix-up ADR-071 exists to
  prevent.
- `Journal.visible` used `User.current` while `editable_by?(user)` used the
  argument, and rejected journal requests (400/403) left no log line.

## Original Code

```ruby
begin
  context ||= build_completion_context(...)
  ...
  completion = chat(messages, {})
rescue Faraday::TimeoutError => e
  ...
rescue => e
  ""
end
...
writer = journal&.user || User.current
journal = Journal.visible.find_by(id: journal_id)
```

## Fix

The context and prompt are built outside any rescue; only `chat` is guarded,
and the agent and `Llm` rescue `RubyLLM::Error` / `Faraday::Error` only. A
journal without a user raises `ArgumentError`. The resolver uses
`Journal.visible(user)` and logs each rejection with journal, issue and user
id. Tests: a context defect and a prompt error now raise; a `nil`-user journal
raises; a private note is rejected for the given user while `User.current` is
an admin. Documented in ADR-071.

## Root Cause

The AI added new logic inside an existing method and kept its surrounding
`rescue`, assuming the pre-existing handler was correct. AGENTS.md says a
rescue lists the error classes of the external call and wraps only that call,
but the AI treated the old rescue as out of scope. `|| User.current` was
written as a convenient default for "no journal" and also absorbed "journal
without user".

## Prevention

When new code lands inside a method that already has `rescue => e` /
`rescue StandardError`, move the new code out of the `begin` and narrow the
rescue to the external call's classes in the same change. Never use `a || b`
where `a` can be nil for a reason other than "not given": branch on whether
the input was given, and raise on the invalid case. A function that takes a
`user` argument passes it to every permission-scoped call it makes.

**Promoted to**: Not yet
