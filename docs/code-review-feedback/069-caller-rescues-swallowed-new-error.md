# CRF-069: Existing broad rescues in callers swallowed the new error from the shared attachment path

**Date**: 2026-10-21
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, simplify)
**Feature**: branch `080-office-attachment-markdown`
**Files**: lib/redmine_ai_helper/vector/issue_content_analyzer.rb, lib/redmine_ai_helper/tools/vector_tools.rb, test/unit/vector/issue_content_analyzer_test.rb, test/unit/tools/vector_tools_test.rb
**Category**: error-handling
**Related**: CRF-014, CRF-022

## Feedback

errors review: research R-005/R-007 said an `EncodingError` from `supported_attachment_paths` propagates to callers, but `IssueContentAnalyzer#analyze` wrapped its whole body in `rescue StandardError` (returning an empty analysis), and `VectorTools#build_hybrid_query` wrapped `analyze` in `rescue => e` (falling back to a plain query). Research R-012 had listed the analyzer as "no change needed".

## Original Code

```ruby
  file_paths = supported_attachment_paths(issue)
  ...
  response = call_llm(messages, with: file_paths.presence, schema: schema_payload)
  parse_response(response, messages, with: file_paths.presence)
rescue StandardError => e
  ai_helper_logger.warn("Failed to analyze issue content: #{e.message}")
  empty_result
```

## Fix

With the user's approval: `analyze` rescues only `RubyLLM::Error, Faraday::Error` around `call_llm` (log names the issue id and error class); `build_hybrid_query` has no rescue, because LLM API/network errors are already handled inside `analyze` and anything else must surface. Tests: API and network errors still give an empty result; `ConfigurationError` and `EncodingError` raise; the similar-issue search raises instead of searching with a plain query.

## Root Cause

When listing callers of the shared path (SF-003/SF-015), the AI checked only how each caller uses the return value (`with: result.presence`), not how each caller handles exceptions from it. The new raise was designed as "surface the error", but that claim depends on every caller's rescue, which was not read.

## Prevention

When a change adds a new exception to a shared code path, read the rescue clauses of every caller up to the entry point, and record in the caller table whether the exception reaches the user; a caller with `rescue StandardError`/`rescue => e` around the call is "affected" and must be narrowed or explicitly accepted by the user.

**Promoted to**: AGENTS.md
