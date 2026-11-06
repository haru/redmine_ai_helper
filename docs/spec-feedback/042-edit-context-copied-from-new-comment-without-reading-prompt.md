# SF-042: Gave an edited comment the new-comment completion context without reading what the prompt does with it

**Date**: 2026-11-03
**Feature**: specs/085-journal-edit-typo-completion (branch `feature/085-journal-edit-typo-completion`)
**Artifact**: spec.md
**Category**: unconfirmed-assumption
**Related**: SF-011

## Feedback

During `/speckit-clarify` the AI asked: "When an older comment is edited, should comments posted after it also be given to the AI as context?" It gave an example: if comment #3 ("An error appears on the login screen.") is edited after #4 ("Which browser?") and #5 ("Chrome.") were posted, giving #4 and #5 lets the AI suggest text that anticipates the later conversation. The user chose option B: "Give only the comments posted before the comment being edited (up to 20)."

## What the AI Wrote

- FR-005: "Auto-completion suggestions in a comment edit form MUST use the same issue context as new-comment suggestions (the issue and its recent non-private comments), except that the comment being edited MUST be left out of the recent comments."
- Edge case: "The edited comment is older than the most recent comments used as context: nothing is left out, and the context is the same as for a new comment."

Both carried over the new-comment context, the latest 20 non-private comments, which include comments posted after the edited one.

## Correction

- FR-005 now says the conversation history contains only non-private comments posted before the comment being edited (the most recent 20 of them). The edited comment and comments posted after it are excluded, "so that suggestions follow the conversation as it was when the comment was written."
- The "older than the most recent comments" edge case was replaced by two edge cases: the first comment on the issue gets an empty history, and comments posted after the edited one are not given to the AI.

## Root Cause

The AI wrote the edit-form behaviour as "same as the new-comment field" because issue #551 framed the feature as reusing the existing aids. It read `IssueReadAgent`'s note-context code (`issue_read_agent.rb`, "latest 20 with notes") to find the duplication of the edited comment itself, but it did not read the prompt that consumes that context, `assets/prompt_templates/issue_read_agent/note_inline_completion.yml`. The prompt calls the list "Recent Conversation History" and instructs the AI to "Consider the conversation history and respond appropriately to previous comments". The prompt assumes every listed comment comes before the text being written. That holds for a new comment but not for an older comment being edited. The AI checked what data goes into the context but not what the prompt tells the AI to do with it, so it did not see that the reused data has a different meaning in the new situation.

## Prevention

When a spec reuses an existing LLM feature in a new situation (a different form, object, or point in time), read the prompt template that consumes the reused context, not only the code that builds it. For each instruction in the prompt that relies on an ordering or relationship ("previous comments", "the current page", "the latest version"), check that it still holds in the new situation. If it does not, ask the user how the context should change instead of writing "same as the existing feature".

**Promoted to**: Not yet
