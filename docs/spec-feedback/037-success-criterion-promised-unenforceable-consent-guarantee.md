# SF-037: Success criterion promised a consent guarantee that the tools cannot enforce

**Date**: 2026-11-02
**Feature**: specs/084-project-management-tools (branch `feature/084-project-management-tools`)
**Artifact**: spec.md (SC-005, FR-009a)
**Category**: unconfirmed-assumption
**Related**: None

## Feedback

In `/speckit-clarify`, asked how strongly "not executed without consent" must be guaranteed (the LLM decides whether to ask; MCP clients call tools directly), the user chose: "guarantee by instruction only — state 'always confirm with the user before running' in the agent instructions and the tool descriptions, the same as the existing delete_version; the tools do not verify consent."

## What the AI Wrote

> SC-005: Project creation, private→public switching, member removal, and disabling the AI Helper module are never executed without the user's explicit consent.

## Correction

- New FR-009a: confirmation is required by wording in the ProjectAgent instructions and the tool descriptions (same as delete_version); MCP clients see the same descriptions; the tools do not check consent.
- SC-005 rewritten: for each of those operations, both the ProjectAgent instructions and the tool description contain wording that requires confirmation before running.

## Root Cause

The AI wrote the success criterion as the behaviour it wanted ("never without consent") without checking which layer could enforce it. In this plugin, confirmation is a prompt instruction followed by the LLM (`leader_agent/system_prompt.yml`, the delete_version description in `version_write_tools.rb`), and `AiHelperMcpController` exposes every BaseTools function to external MCP clients that the plugin does not control. No test can show "never", so the criterion was unverifiable as written.

## Prevention

Before a spec states that the AI "never" or "always" does something, name the layer that enforces it (code check, permission, prompt instruction). When only a prompt instruction enforces it, write the criterion as "the instruction is present in <places>" and ask the user if a stronger guarantee is expected.

**Promoted to**: Not yet
