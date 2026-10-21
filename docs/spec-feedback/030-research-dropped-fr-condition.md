# SF-030: Research decision dropped the condition that the FR put on the UTF-8 repair

**Date**: 2026-10-21
**Feature**: specs/080-office-attachment-markdown (branch `080-office-attachment-markdown`)
**Artifact**: research.md (R-007), plan.md, data-model.md, quickstart.md, contracts/attachment_file_helper.md
**Category**: scope-gap
**Related**: None

## Feedback

A local AI review (errors, tests) pointed out that the code removed an incomplete last character from every conversion result, which silently repairs a damaged cache below the output limit. The user asked for all review findings to be fixed, which included limiting the repair to results that reached the limit.

## What the AI Wrote

FR-006 (spec): "本体の切り詰めによって末尾のマルチバイト文字が途中で切れている場合は、その不完全な末尾だけを取り除かなければならない" (only when Redmine's truncation cut the last character).

R-007 Decision: "正しくなければ末尾を 1〜3 バイトずつ削って正しくなった時点の文字列を使う" (if invalid, trim 1–3 trailing bytes until valid) — with no truncation condition. plan.md, data-model.md and quickstart.md repeated the unconditional rule.

## Correction

R-007 now trims only when R-006 judged the result truncated, bounded by the result size, and only when the trimmed bytes are an incomplete lead sequence; anything else, including an incomplete last character below the limit, raises `EncodingError`. plan.md, data-model.md, quickstart.md (#8, #9) and the contract were aligned.

## Root Cause

The rationale in R-007 explained why truncation is the only legitimate cause, but the decision line was written as a byte-level algorithm without carrying that cause into a condition. The AI did not compare the decision against the exact FR-006 wording afterwards, and plan/data-model copied the decision, not the FR.

## Prevention

When a research decision implements an FR that is conditional ("when X, do Y"), the decision states condition X explicitly, and the test list includes the case "not X" with its expected outcome.

**Promoted to**: Not yet
