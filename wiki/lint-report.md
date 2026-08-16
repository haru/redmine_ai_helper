# Wiki Lint Report — 2026-08-16

Scope: full pass over 32 pages, 23 sources.
Config: defaults (no `.specify/extensions/wiki/wiki-config.yml`) —
`stale_after_days: 90`, `require_citations: true`, `auto_fix: index-and-links`.

Run after ingesting **S023** (`docs/adr/019-teams-single-tenant-bot.md`), which
amends the multi-tenant premise of ADR-018.

## Check results

| Check | Result |
|---|---|
| index-drift | clean — 32/32 pages indexed, no dead index links; no new pages were created this pass, so `INDEX.md` needed no regeneration |
| links | clean — 0 broken relative links; all cited IDs resolve to S001–S023 (`RS256` in teams-request-verification.md is not an S-id) |
| orphans | clean — every page has ≥1 inbound link from another page |
| contradictions | 0 outstanding — no `> ⚠ conflict:` markers. The four pages sharing S021/S022 with the new S023 (teams-reply-delivery.md, teams-request-verification.md, teams-adapter.md, chat-channel-gateway-architecture.md) were updated in the same pass, so no page still asserts the multi-tenant token endpoint or the multi-tenant justification |
| stale | 1 finding, open (carried over as finding 5 of the 2026-08-14 pass) — clean by date (oldest page 2026-08-01, well inside 90 days) and clean by re-ingest (every page citing S023 is dated 2026-08-16) |
| citations | clean — the claims added this pass cite S023; no uncited claims remain |

## Findings

| # | Check | Severity | Page | Finding | Suggested fix |
|---|-------|----------|------|---------|---------------|
| 1 | stale | structural | agent-write-capability-routing.md, mcp-integration.md, inbound-webhook-endpoint.md | Over the SCHEMA 600-word split rule, excluding frontmatter and Related: 643, 620, 619 words. Unchanged since the 2026-08-14 pass | **Open** — each needs a topical split into a linked page pair, following the inbound-event-queue.md → inbound-reply-metadata.md and teams-adapter.md → teams-reply-delivery.md precedents |

## Verified, no finding

- **teams-graph-history.md** (2026-08-14, S021/S022) predates S023 but none of its
  claims are invalidated: it already documented the Graph token as coming from
  `https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/token`, which is now
  simply the endpoint both tokens share.
- **teams-request-verification.md** grew to 639 words including its Related
  section; measured the way the 2026-08-14 pass measured (frontmatter and
  Related excluded) it stays under the 600-word split rule.
