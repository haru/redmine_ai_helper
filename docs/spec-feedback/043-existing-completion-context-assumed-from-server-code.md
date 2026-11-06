# SF-043: Described the new-comment completion context from the server code without checking what the browser sends

**Date**: 2026-11-03
**Feature**: specs/085-journal-edit-typo-completion (branch `feature/085-journal-edit-typo-completion`)
**Artifact**: spec.md
**Category**: unconfirmed-assumption
**Related**: SF-042

## Feedback

During `/speckit-plan` the AI found that the spec described a behaviour the new-comment field does not have, and asked the user how to proceed. The user chose: "Use the note context in both forms" (fix the new-comment field too), "Order them newest first" (fix the comment order for both forms), and "Keep the current 5-in-the-prompt rule" (keep the 20 / 5 limits).

## What the AI Wrote

- Background: "Auto-completion: ... the suggestion is based on the issue and its recent comments."
- FR-005: "... (the most recent 20 of them, the same limit as for new comments)."
- FR-005a: "Auto-completion for the new-comment field MUST keep using all recent non-private comments as context (no comment is left out)."
- FR-009: "The existing aids for the issue description and new-comment fields MUST keep their current behaviour."

In fact:

1. The browser never sends `context_type` (`AiHelperAutoCompletion#buildDefaultRequestBody` sends only `text` / `cursor_position`), so the server falls back to `"description"` and the new-comment field uses the issue-description prompt with no comment history, writer, or role.
2. `IssueReadAgent#build_note_specific_context` takes `first(20)` of `issue.journals`, which has no order (the code comment "Already sorted by created_on desc" is wrong), so it takes the oldest 20.
3. Only the first 5 of the 20 are written into the prompt (`format_recent_notes`, `notes[0..4]`).

## Correction

- Background now states that the comment prompt exists but the new-comment field does not use it, and that the comment context picks the oldest comments.
- FR-005a now requires the new-comment field to use the comment context and says this changes current behaviour.
- New FR-005c: candidates ordered newest first; 20 used for the writer's role, the newest 5 of them in the prompt.
- FR-005 refers to FR-005c instead of "the most recent 20"; FR-009 and SC-004 name the FR-005a / FR-005c change as the exception.
- Three Q&A added under "Session 2026-11-03 (planning)" in Clarifications.

## Root Cause

The AI described the existing feature from the server-side code it read for SF-042: the note context builder in `issue_read_agent.rb` and the prompt `note_inline_completion.yml`. It took the existence of that path as proof that the new-comment field uses it, without reading the browser request that selects the path (`context_type` in `ai_helper_auto_completion.js`) or the controller default (`data["context_type"] || "description"`). It also trusted the code comment about ordering instead of checking the `has_many :journals` association, and read "latest 20" from the variable name without reading how many reach the prompt. The server functional tests send `context_type: "note"` explicitly, so nothing in the test suite showed that the real browser does not.

## Prevention

When a spec says an existing feature "uses X" or "keeps using X", trace one real request from the user's action to the point where X is chosen: the browser request body (or the caller's arguments), the server's default for a missing value, and the branch that picks the code path. Do not take a code comment's claim about ordering, filtering, or limits as fact; check the query or association it describes, and check how much of the built data actually reaches the output (prompt, response).

**Promoted to**: Not yet
