# SF-007: Excluded Discord from a feature to restore a reaction removed from both chat adapters

**Date**: 2026-10-13
**Feature**: specs/072-restore-slack-processing-reaction (branch `072-restore-slack-processing-reaction`)
**Artifact**: spec.md
**Category**: scope-gap
**Related**: SF-003

## Feedback

After the spec was written, the user asked: "Please include Discord as well."

## What the AI Wrote

The spec took Issue #508 (titled "Restore Slack Gateway processing reaction") as its scope boundary and
excluded the other adapter explicitly:

> The target of this feature is the Slack adapter only. ... restoring the Discord adapter's processing
> reaction (also removed in PR #358) is out of scope.
>
> FR-008: The behaviour of the Discord adapter MUST NOT be changed (this feature targets Slack only).

## Correction

Discord was added to scope: user stories and acceptance scenarios for Discord, a requirement that the
reaction is applied in the channel the message actually arrived in (thread, channel, or DM), the Discord
setup guide and the Add Reactions permission in the documentation requirement, and the Assumptions.

## Root Cause

The AI relied on the issue title and body, which only mention Slack. While investigating, it had already
seen that commit 0aaad037 (PR #358) removed the same `notify_processing` reaction from both the Slack and
Discord adapters, and that `docs/discord_gateway_setup.md` still documents the hourglass reaction and the
Add Reactions permission. It saw this evidence but treated the reporter's wording as the scope boundary
instead of asking whether the identical regression in the sibling adapter should be fixed too. It
excluded Discord by assumption rather than presenting it as a scope decision.

## Prevention

When a request restores or changes something that a past commit removed or changed, list every file and
adapter that commit touched. If it covers more than the request names (e.g. both chat adapters), do not
exclude the others by assumption: either include them or put the inclusion/exclusion to the user as an
explicit scope question before writing "out of scope" in the spec.

**Promoted to**: AGENTS.md
