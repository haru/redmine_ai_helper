# SF-039: Added "regardless of the creator's permission" to the user's choice to always enable the AI Helper module

**Date**: 2026-11-02
**Feature**: specs/084-project-management-tools (branch `feature/084-project-management-tools`)
**Artifact**: spec.md (FR-011, US2 scenario 7, Edge Cases, SC-007)
**Category**: scope-creep
**Related**: SF-018

## Feedback

While applying SF-038, the AI asked how "always enable the AI Helper module on new projects" fits with mandatory object-permission checks. The user chose: enable it only when the creator may select modules (an administrator, or the role given to non-admin creators has the select-modules permission); otherwise create the project with the default modules and tell the user the AI Helper module was not enabled.

## What the AI Wrote

The user's earlier answer was the option "always enable it (recommended)". The AI wrote:

> FR-011: ... However, the AI Helper module must always be enabled regardless of this setting or the creator's permissions.
> SC-007: 100% of projects created by the AI have the AI Helper module enabled.

## Correction

FR-011, US2 scenario 7 (plus new 7a), the Edge Cases bullet, and SC-007 now enable the AI Helper module only when the creator may select modules, and report when it was not enabled.

## Root Cause

The option the user chose said "always enable", and its description named only Redmine's default-module setting. The AI extended "always" to also override the creator's module-selection permission (`Project` safe attribute `enabled_module_names`, which for a new record requires admin or `default_member_role` with `select_project_modules`). That is a permission bypass the option never mentioned and the user never chose.

## Prevention

When writing a clarification answer into the spec, keep it to what the chosen option's text said. If applying it would also override a permission or validation that the option did not mention, ask before writing it.

**Promoted to**: AGENTS.md
