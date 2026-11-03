# SF-036: Reused the "confirm only deletions" policy without checking that new operations are reversible

**Date**: 2026-11-02
**Feature**: specs/084-project-management-tools (branch `feature/084-project-management-tools`)
**Artifact**: spec.md (User Story 2 scenario 1, Assumptions, FR-009, SC-005)
**Category**: unconfirmed-assumption
**Related**: None

## Feedback

In `/speckit-clarify`, asked which operations other than member removal need user confirmation before the AI runs them, the user chose: "confirm before creating a project and before switching a project from private to public; run other creates and updates without confirmation."

## What the AI Wrote

spec.md required confirmation only for member removal, and project creation ran directly:

> US2-1: **When** a project creation is requested with a name and identifier, **Then** the project is created and the AI reports its name, identifier, and URL
> Assumptions: the confirmation policy for member removal follows the existing delete tools (version deletion): "confirm with the user before running".

## Correction

- New FR-009: the AI obtains explicit consent before project creation, private→public switching (included in the creation confirmation when a new project is public), member removal, and disabling the AI Helper module. Other creates and updates (including tracker assign/unassign) run without confirmation.
- US2-1 now shows the creation details and waits for consent; new US2-9/10 scenarios cover the public switch (confirmed) and a plain update (not confirmed).
- SC-005 and the Assumptions were updated to the same list.

## Root Cause

The AI took the existing rule in `leader_agent/system_prompt.yml` ("confirm deletions because they are irreversible; creating or updating can be done without confirmation, as mistakes can be corrected afterward") and applied it by operation type: removal → confirm, create/update → no confirm. It did not check the rule's premise — "mistakes can be corrected afterward" — against this feature. The feature explicitly adds no delete tool, so a wrongly created project cannot be undone from the AI; and a private→public switch exposes data to everyone immediately, so it cannot be undone either. Both are irreversible in effect although they are "create/update".

## Prevention

When a spec reuses an existing confirmation (or safety) policy, check each new operation against the policy's stated premise (e.g. "can be corrected afterward") rather than against its operation type. An operation whose effect cannot be undone with the tools the feature provides, or that exposes data at once, is listed as a question for the user before the spec says it runs without confirmation.

**Promoted to**: Not yet
