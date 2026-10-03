# ADR-045: Health Report Edits Keep the Original and the Latest Version Only

**Date**: 2026-10-03
**Status**: Accepted

## Context

Users with the new `edit_ai_helper_health_reports` permission can correct the
body of a stored report. The AI-generated text must stay available, and
concurrent edits must not silently overwrite each other. A full revision
history was judged out of scope.

## Decision

- The first edit stores the AI-generated body in `original_health_report`;
  later edits never touch it. Only the latest edit is recorded in
  `last_edited_by_id` / `last_edited_on`.
- A report counts as edited when `last_edited_on` is present. The state is
  irreversible: saving text identical to the original does not reset it.
- Concurrent edits are detected with Rails optimistic locking
  (`lock_version`); a stale submission returns 409 and keeps the user's input
  in the form.
- CR characters are removed before comparison and storage, so a browser's
  CRLF form submission of unchanged text is a no-op (no edit is recorded and
  the lock version is unchanged).
- When a user is destroyed, `last_edited_by_id` is reassigned to the
  anonymous user so the report stays marked as edited.

## Consequences

- Intermediate versions are lost; only original and latest are viewable.
- Comparison and analysis features operate on the edited body.
