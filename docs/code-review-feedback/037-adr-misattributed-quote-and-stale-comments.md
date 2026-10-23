# CRF-037: ADR quoted a decision from the wrong source; comments and promotion fields were inaccurate

**Date**: 2026-10-16
**Source**: Local AI review (`/speckit-review-run`, comments agent)
**Feature**: branch `bugfix/076-fix-health-report-table-style`
**Files**: docs/adr/057-ai-output-tables-styled-on-the-server.md, wiki/pages/health-report-markdown-rendering.md, app/helpers/ai_helper_helper.rb, assets/stylesheets/ai_helper.css, docs/spec-feedback/003-missed-leader-system-prompt.md, docs/spec-feedback/007-excluded-discord-from-shared-removal.md, docs/spec-feedback/README.md
**Category**: doc-comment
**Related**: CRF-005, CRF-011, CRF-023 (rule in AGENTS.md), CRF-032

## Feedback

- ADR-057 and the wiki quoted a sentence as ADR-044's rejection of client-side rendering. ADR-044 has no such text; it comes from `specs/064-health-report-edit/research.md`. The wiki also said the rejection was "fully enforced" although a freshly streamed report is still rendered by the JS parser.
- The `set_list_class_on_tables` comment gave the wrong reason for the order (the sanitizer would strip `list` if the class were set before it), `md_to_html` did not document its `ArgumentError`, and Redmine versions were written as "6.1/master" instead of 6.x/7.x.
- The CSS comment did not say that `#aihelper-chat-conversation` also contains the streamed answer.
- SF-003 and SF-007 are sources of a rule added to AGENTS.md but still said `Not yet`.

## Original Code

```markdown
ADR-044 already rejected client-side rendering for display ("HTML must come from ERB; ...")
```

## Fix

The ADR cites the feature 064 research and no longer attributes the quote to ADR-044; the wiki scopes the claim to saved reports; the comments, YARD tags and version names were corrected; the two spec-feedback entries and their index cells now say `AGENTS.md`.

## Root Cause

The AI summarized the decision from memory of the wiki instead of opening the cited ADR, and wrote comments from its own intent rather than re-reading the code they describe. When it added a rule to AGENTS.md it updated only the entry that triggered it.

## Prevention

- Open the cited ADR or research section in the same step and copy its wording; a quoted sentence must be found by `grep` in the cited file.
- When a rule is added to AGENTS.md from several entries, update the **Promoted to** field of every source entry and its index cell in the same change.
- A comment that states why code is ordered or placed a certain way names the concrete effect of the opposite order.

**Promoted to**: Not yet
