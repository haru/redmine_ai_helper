# CRF-111: Re-render restored the description toggle from a storage key shared with the notes toggle

**Date**: 2026-11-21
**Source**: GitHub Copilot (PR #574)
**Feature**: branch `bugfix/088-fix-issue-form-rerender` / PR #574
**Files**: assets/javascripts/autocompletion/ai_helper_issue_autocompletion.js, assets/javascripts/autocompletion/ai_helper_auto_completion.js, specs/088-fix-issue-form-rerender/research.md, docs/adr/073-issue-form-aids-reattach-on-rerender.md, wiki/pages/issue-form-rerender-resilience.md
**Category**: edge-case
**Related**: CRF-107

## Feedback

Description and notes completion share one persisted setting, but their checkbox states can differ. Enabling notes while description is off makes the replacement completion's `init()` enable description after a tracker/status re-render, and the reverse disables it. Capture the departing description state before teardown and restore it on the replacement instance.
(<https://github.com/haru/redmine_ai_helper/pull/574#discussion_r4650857061>)

## Original Code

Nothing: research R-006 decided that the new instance's `init()` → `loadSettings()` reads the per-user key `aiHelperAutoCompletion_<userId>`, so the state "carries over with no code" (FR-006).

## Fix

`releaseDetached()` records the released description completion's `isEnabled`; the next render's completion calls the new `AiHelperAutoCompletion#restoreEnabled(enabled)` after `init()`, which sets the checkbox and `isEnabled` without writing storage and throws `TypeError` on a non-boolean. The state survives a render without a description editor. Tests set opposite description/notes states through their change events and re-render. R-006, ADR-073 and the wiki page were corrected.

## Root Cause

The AI read `loadSettings()`/`saveSettings()` and concluded the key round-trips the description state, without checking who else writes the key. `storageKey` depends only on the user id, so every completion instance on the page (description and notes) writes it. The existing FR-006 test set the key directly instead of toggling another field, so it could not see the conflict.

## Prevention

Before relying on persisted state (localStorage, session, cookie) to carry one element's state across a rebuild, grep every writer of that key; if anything else on the same page writes it, carry the departing instance's in-memory state instead. The test changes the other writer's state to the opposite value before the rebuild.

**Promoted to**: Not yet
