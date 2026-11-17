# SF-044: Test plan prescribed test-store internals and built the precondition through the code under test

**Date**: 2026-11-17
**Feature**: specs/086-fix-session-conversation-id (branch `bugfix/086-fix-session-conversation-id`)
**Artifact**: research.md (R-003), plan.md (integration test section), tasks.md (T003, T010)
**Category**: granularity
**Related**: None

## Feedback

A review of the implemented tests found that the tests differ from the plan. The user asked to change the specification to match the tests (and to fix the remaining review findings in the code).

## What the AI Wrote

- R-003, plan.md and T003 prescribed how the test-only session store keeps data: "reads saved Marshal data" and "saves with Marshal".
- plan.md "Test 2" and T010 prescribed: "create conversations A and B (both through `chat` -> `call_llm`). While B is displayed, select A with `conversation` (GET)".
- plan.md "Test 1" ended after the second `chat` -> `call_llm` and did not cover US1 scenario 3 (reload shows the conversation).

## Correction

- The store description now says `deep_dup` (Marshal and `deep_dup` both keep symbol keys, so the result is the same; `deep_dup` is simpler).
- Test 2 / T010 now create A and B with `AiHelperConversation.create!` and write B into the stored session directly, and assert before the GET that the stored session does not point at A. The effect of the switch can then only come from `set_conversation_id` in `conversation` (CRF-051).
- Test 1 / T010 now end with a `reload` request (US1 scenario 3, US2 scenario 2).

## Root Cause

The plan described the internals of test helpers (serialization format) that do not matter to the requirement, so they drifted from the implementation. It also built the "B is displayed" precondition through the same controller path that the test is meant to guard, which the project's CRF-051 rule says to avoid, and it left one acceptance scenario (US1 scenario 3) without a test step. The AI should have mapped every acceptance scenario to a test step and arranged preconditions independently of the code under test when writing the plan.

## Prevention

When a plan or tasks file describes a test, (1) map each acceptance scenario to a named test step and check none is missing, (2) state the precondition and how it is set up without calling the code under test, and (3) describe test-helper behaviour only as far as the requirement needs it (for example "keeps the loaded value and skips the write when equal"), not its storage or serialization format.

**Promoted to**: Not yet
