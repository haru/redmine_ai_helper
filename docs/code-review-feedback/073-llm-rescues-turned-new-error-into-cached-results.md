# CRF-073: Llm#wiki_summary and #project_health_report turned the new ArgumentError into saved or served results

**Date**: 2026-10-21
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, types, simplify)
**Feature**: branch `081-fix-prompt-template-validation`
**Files**: lib/redmine_ai_helper/llm.rb, app/controllers/ai_helper_controller.rb, app/controllers/concerns/ai_helper/streaming.rb, test/unit/llm_test.rb, test/functional/ai_helper_controller_test.rb, test/integration/api/health_report_test.rb
**Category**: error-handling
**Related**: CRF-069, CRF-054, CRF-014

## Feedback

errors review: both methods wrapped their body in `rescue => e` and returned `e.message`, so a template/caller mismatch (the new `ArgumentError`) was stored as the cached wiki summary, and the REST health report API ignored the failure and returned the previous report with HTTP 200 (or a `NoMethodError` 500 when none existed). `Llm#issue_summary` had already been fixed to re-raise for the same reason. Three existing tests depended on the swallowed error.

## Original Code

```ruby
rescue => e
  ai_helper_logger.error "error: #{e.full_message}"
  answer = e.message
  stream_proc.call(answer) if stream_proc
end
```

## Fix

Both methods now raise. `generate_wiki_summary` and `generate_project_health` rescue inside the stream block (`stream_llm_response` closes the stream in `ensure`, so the old outer rescue could no longer write) through the new `report_stream_failure`; nothing is cached on failure. Tests that relied on the swallowed error now stub the LLM.

## Root Cause

ADR-063 and research recorded "existing broad rescues are not changed, caller tests guard them" and the AI accepted that for all callers. CRF-069 (same defect class, one feature earlier) had already shown that the caller table must say whether a new exception reaches the user, but the rescues around `Llm` methods that persist their return value were not traced to the controller.

## Prevention

When a change adds an exception to a shared path, trace each caller that persists or serves the rescue's return value (cache, DB, API response) and make that caller re-raise or report the failure; "the tests will catch a mismatch" does not cover a template that breaks in production. Run the controller tests with the LLM unstubbed once to find tests that only pass on a swallowed error.

**Promoted to**: Not yet
