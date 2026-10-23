# SF-031: Put the template file path in an exception message without checking where the message goes

**Date**: 2026-10-21
**Feature**: specs/081-fix-prompt-template-validation (branch `081-fix-prompt-template-validation`)
**Artifact**: spec.md (FR-002a, SC-005, Clarifications), plan.md, research.md, contracts/
**Category**: convention-unknown
**Related**: SF-029

## Feedback

During planning the AI pointed out that the `ArgumentError` message would carry the template's disk path, and that callers' `rescue => e` blocks might show `e.message` to end users or the LLM. The user decided: do not put the path in the exception message; restrict it to the log output.

## What the AI Wrote

FR-002a: "When validation fails, the `ArgumentError` message MUST include the file path" of the template loaded from YAML (derived from a clarification answer "include identifying information in the message"). The spec also listed the callers' `rescue => e` blocks, but only as to whether `ArgumentError` is caught, not whether `e.message` reaches users or the LLM.

## Correction

FR-002a now requires an `ai_helper_logger` error log carrying the file path and the missing/unknown variable names before the `ArgumentError` is raised. The exception message carries variable names only. SC-005, the edge case on path-less templates and the Clarifications section were updated; plan.md, research.md (R-004), the contract and quickstart follow.

## Root Cause

The AI treated "identify the template" as a message-content question and answered it with the most convenient place, the exception message. The constitution (Principle V: disk paths must never be embedded in text sent to LLMs) and the existing caller audit (SF-029) were both available. The audit covered whether callers catch the exception but not what they do with `e.message`, so the path exposure was only noticed after the spec was written.

## Prevention

When a spec puts a value into an exception message, check every caller's `rescue` for where `e.message` goes (user response, LLM input, log). Disk paths, credentials and other internal details go to logs only, never into the message, unless every such caller is confirmed not to expose it.

**Promoted to**: Not yet
