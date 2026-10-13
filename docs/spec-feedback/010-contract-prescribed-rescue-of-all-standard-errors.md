# SF-010: Contract prescribed rescuing every StandardError from the adapter calls

**Date**: 2026-10-13
**Feature**: specs/073-chat-channel-progress (branch `073-chat-channel-progress`)
**Artifact**: contracts/progress_message.md (C-5), research.md (R-004)
**Category**: convention-unknown
**Related**: SF-006, SF-009

## Feedback

A local review (`/speckit-review-run`) found that the reporter rescued `StandardError` around whole adapter methods, hiding adapter bugs, although ADR-054 said only failures of the adapter call were rescued. The user approved changing the spec so that only the transport errors an adapter declares are rescued ("I approve the spec change. Record it in the feedback.").

## What the AI Wrote

- contracts C-5: "`StandardError` from the adapter calls is rescued; `ai_helper_logger.error "chat channel: failed to <post|update|delete> progress message on <channel_type> thread <thread_key>: <full_message>"` is logged and the call returns. The exception is not passed to the caller (FR-006)."
- research.md R-004: "`ProgressReporter#call` / `#finish` rescue every `StandardError` from the adapter calls and log it."
- tasks T027 said the scope was "limited to the adapter call line", which the contract's `StandardError` contradicted.

## Correction

- C-5 and R-004 now say that only the errors listed by `adapter.progress_errors` (API errors, unparsable responses, network failures) are rescued; other errors, including adapter bugs, surface. A `post_progress` that does not return a `Handle` is logged as a `TypeError` and disables progress. The log line names the posted message once one exists.
- Code, tests, ADR-054, the wiki page and CRF-022 were updated in the same change.

## Root Cause

The AI copied the error-handling contract of the previous feature (072, ADR-053) and its "rescue StandardError" wording without asking what the rescue is allowed to hide. SF-006 and CRF-014 had already recorded the same mistake for web search, but the rule existed only in those logs, not in AGENTS.md. The prescribed scope (whole adapter method) also contradicted the ADR text it wrote in the same change.

## Prevention

When a spec or contract prescribes a rescue that turns failures into a result value, it names the error classes the external call can raise (API, network, parse) and says every other error surfaces. It never says "StandardError". Check that the contract, plan and ADR describe the same rescue scope.

**Promoted to**: AGENTS.md
