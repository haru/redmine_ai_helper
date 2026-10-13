# SF-008: Reaction lifecycle requirements written without reading the gateway queue and shutdown code

**Date**: 2026-10-13
**Feature**: specs/072-restore-slack-processing-reaction (branch `072-restore-slack-processing-reaction`)
**Artifact**: spec.md
**Category**: convention-unknown
**Related**: SF-005, SF-006, SF-007

## Feedback

Raised through `/speckit-clarify`. Two questions exposed the problem and the user answered "A" to both:

1. When is the hourglass added: on receipt (when the message is queued) or when the worker starts it? The user chose on receipt.
2. On a stop request, are queued questions still processed or discarded? The user chose to keep the existing behaviour (process and answer them) and add no shutdown-specific removal.

## What the AI Wrote

- FR-001 said the reaction is added "right after processing of the message starts", while FR-002 and the
  Edge Cases said it stays while the message waits in the queue: the spec contradicted itself.
- US4 / FR-006 / SC-004 required the gateway to remove the hourglass on a stop request, "as far as
  possible (best effort)", for the message in progress.

## Correction

- FR-001 now adds the reaction when the message is received and queued, before the worker starts it.
- US4, FR-006, SC-004 and the Assumptions now say that on shutdown the gateway keeps its existing
  behaviour (finish the in-progress and queued questions); each reaction is removed when its question
  finishes, and no shutdown-specific removal is added.

## Root Cause

The lifecycle requirements were written from the issue text and from the old removed implementation. The
AI did not read `lib/redmine_ai_helper/chat_channel/gateway.rb` first. `Gateway#worker_loop` serializes
all messages through one worker with a `SizedQueue`, and `Gateway#shutdown` already drains whatever was
queued before the shutdown marker. Reading it would have shown (a) that "processing started" and
"received" are different moments because of the queue, and (b) that a dedicated removal on shutdown is
redundant. The contradiction was only caught when the AI prepared clarification questions.

## Prevention

Before writing a requirement about timing or lifecycle (when something starts, ends, or happens on
shutdown), read the code that owns that lifecycle (here the gateway's queue, worker, and shutdown) and
state in the spec which existing behaviour the requirement relies on. After drafting, check that no two
requirements use different start or end points for the same state.

**Promoted to**: AGENTS.md
