# CRF-101: Wiki page kept the overstated cookie store claim already corrected in the test comments

**Date**: 2026-11-17
**Source**: GitHub Copilot (PR #569)
**Feature**: branch `bugfix/086-fix-session-conversation-id` / PR #569
**Files**: wiki/pages/session-conversation-id-persistence.md
**Category**: doc-comment
**Related**: CRF-100, CRF-007, CRF-005

## Feedback

The wiki page said "Redmine's default `cookie_store` serializes the whole session on every response". Rack's cookie session middleware writes only when the session was loaded during the request or a force option is set; what it lacks is nested-change detection. Copilot asked to scope the statement to responses that load the session.
([review comment](https://github.com/haru/redmine_ai_helper/pull/569#discussion_r4599600030))

## Original Code

```markdown
- Redmine's default `cookie_store` serializes the whole session on every response, so
  the bug is invisible there (S062).
```

## Fix

The bullet now says the cookie store re-serializes the session on every response whose request loaded it (Rack's `commit_session?`, rack-session 2.1.2 `abstract/id.rb:350`), that Redmine's `session_store` config sets no force option (`:renew`/`:expire_after`, etc.), that the store has no nested-change detection, and that `create_session` loads the session on every AI Helper action.

## Root Cause

The same overstatement had already been corrected in the integration test comments (CRF-100), but the fix was applied only to the file the local review pointed at. The wiki page was ingested from the same artifacts and repeated the claim; nobody grepped `wiki/` and `docs/` for the corrected wording. AGENTS.md already requires updating docs/ and wiki/ in the same change when a fix corrects a statement (CRF-005, CRF-007), but the rule was not applied to a wording correction of library behaviour.

## Prevention

When a review corrects a statement about library or system behaviour, grep the whole repository (code comments, `docs/`, `wiki/`, specs artifacts that get ingested) for the old claim and correct every occurrence in the same change.

**Promoted to**: Not yet
