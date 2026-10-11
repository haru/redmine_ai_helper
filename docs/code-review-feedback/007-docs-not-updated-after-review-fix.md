# CRF-007: Docs kept describing behaviour that a review fix had changed

**Date**: 2026-10-11
**Source**: GitHub Copilot (PR #499)
**Feature**: branch `feature/069-ruby-llm-2-1-migration` / PR #499
**Files**: docs/adr/050-replace-ruby-llm-mcp-with-built-in-mcp-client.md, docs/mcp_transport_configuration_examples.md, wiki/pages/ruby-llm-2-1-migration.md, wiki/pages/llm-provider-layer.md
**Category**: doc-comment
**Related**: CRF-003, CRF-004, CRF-005

## Feedback

ADR-050, the MCP configuration guide and the migration wiki page still said a failed MCP tool-list lookup leaves the agent without tools, although the CRF-003 fix makes the error propagate and retries on the next lookup. The migration table also mapped the user ID to `with_end_user`, although the CRF-004 fix sends `safety_identifier` via `with_provider_options`.
([r4240337313](https://github.com/haru/redmine_ai_helper/pull/499#discussion_r4240337313), [r4240337335](https://github.com/haru/redmine_ai_helper/pull/499#discussion_r4240337335), [r4240337366](https://github.com/haru/redmine_ai_helper/pull/499#discussion_r4240337366), [r4240337390](https://github.com/haru/redmine_ai_helper/pull/499#discussion_r4240337390))

## Original Code

```markdown
- Connection happens lazily on the first `tools` call. Per-server failures are logged and that agent gets no tools.
| `with_params` → `with_end_user` | still skipped when `supports_user_identifier?` is false |
```

## Fix

Rewrote the four statements to describe error propagation with retry, and `safety_identifier` via `with_provider_options`. The same stale claim in `wiki/pages/llm-provider-layer.md` (not flagged) was fixed too.

## Root Cause

The docs were written from the plan (S042) before the review fixes. When the review fixes changed behaviour (CRF-003, CRF-004), the AI updated code, tests and some docs, but did not grep the docs and wiki for statements describing the old behaviour. The wiki was then ingested from the plan, re-introducing the plan's assumptions.

## Prevention

When a fix changes observable behaviour (error handling, which API sends a value), grep `docs/`, `wiki/`, ADRs created in the same branch, README and AGENTS.md for the old behaviour's wording and API names, and update them in the same change. When ingesting a feature into the wiki, prefer the final code over the plan where they differ.

**Promoted to**: Not yet
