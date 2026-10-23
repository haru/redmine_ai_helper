# SF-029: Caller audit for a new exception checked return-value use but not the callers' rescues

**Date**: 2026-10-21
**Feature**: specs/080-office-attachment-markdown (branch `080-office-attachment-markdown`)
**Artifact**: research.md (R-005, R-007, R-012), contracts/attachment_file_helper.md
**Category**: scope-gap
**Related**: SF-003, SF-007, SF-015

## Feedback

A local AI review (errors) found that the `EncodingError` the research said would "propagate to the caller" was swallowed in vector indexing. The AI then found the same in similar-issue search and asked the user. The user chose to narrow `IssueContentAnalyzer#analyze`'s rescue to `RubyLLM::Error, Faraday::Error` around the LLM call, and to fix `VectorTools#build_hybrid_query` as well (its rescue was removed because LLM errors no longer reach it).

## What the AI Wrote

R-005: "それ以外の例外(ありえないはずのもの)は呼び出し側へ伝播させる" (other exceptions propagate to the caller).

R-012 caller table:

> | `Vector::IssueContentAnalyzer#analyze`(`issue_content_analyzer.rb:45`) | `with: result.presence` | 不要 |

(no change needed). `VectorTools#build_hybrid_query`, which calls `analyze` inside `rescue => e` and falls back to a plain query, was not listed. `analyze` itself ends with `rescue StandardError => e … empty_result`.

## Correction

- R-012: the analyzer row now says "change" with the narrowed rescue; a `VectorTools#build_hybrid_query` row was added ("rescue removed").
- R-005: names the `case`/`when` + `TypeError` handling and points to R-012 for the callers' rescues.
- Contract caller table, ADR-062, docs and tasks updated to match.

## Root Cause

The AI followed SF-003/SF-015's rule and grepped every caller of `supported_attachment_paths`, but it checked only how each caller uses the returned array. The new behaviour in this feature was also an exception, and whether it "propagates" depends on each caller's rescue clauses and on the callers of those callers, which the AI did not read. The table format (caller / use / change) had no column for exception handling, so the gap was not visible.

## Prevention

When a spec adds or relies on an exception from a shared code path, the caller table includes how each caller (up to the entry point) handles that exception; any `rescue StandardError` / `rescue => e` around it is listed as affected, and the user is asked whether to narrow it before the spec says the exception "propagates".

**Promoted to**: AGENTS.md
