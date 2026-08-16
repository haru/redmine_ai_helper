# Wiki Lint Report — 2026-08-16 (second pass)

Scope: full pass over 34 pages, 23 sources.
Config: defaults (no `.specify/extensions/wiki/wiki-config.yml`) —
`stale_after_days: 90`, `require_citations: true`, `auto_fix: index-and-links`.

Run after the `agent-write-capability-routing.md` → `agent-write-step-guard.md`
split, which cleared the largest word-cap offender (643 words) from the previous
report's finding 1.

## Check results

| Check | Result |
|---|---|
| index-drift | clean — 34/34 pages indexed, 34 index links all resolve; the split pair was indexed as two lines at the same time |
| links | clean — 0 broken relative links; every cited ID resolves to S001–S023 (`RS256` in teams-request-verification.md is not an S-id). The links retargeted by the split (mcp-integration.md, multi-agent-architecture.md → agent-write-step-guard.md) all land on the page that now holds the claim |
| orphans | clean — every page has ≥1 inbound link; `agent-write-step-guard.md` is linked from its parent, multi-agent-architecture.md and mcp-integration.md |
| contradictions | **1 finding** (finding 1) — no `> ⚠ conflict:` markers, but the S016/S017 cluster holds a stale claim contradicting its own page. The S018–S023 inbound/Teams cluster was re-checked and stays clean |
| stale | clean by date (oldest page 2026-08-01, 15 days, well inside 90). The 7 pages predating the S021 re-ingest were verified in the earlier pass today and are unchanged since |
| citations | 1 finding (finding 3), carried over unchanged. Split-provenance lead paragraphs on 3 pages carry no S-id by design: they describe the wiki's own structure, not project claims |
| word cap (SCHEMA) | 2 pages over 600 body words — finding 2, down from 3 |

## Findings

| # | Check | Severity | Page | Finding | Suggested fix |
|---|-------|----------|------|---------|---------------|
| 1 | contradictions | semantic | multi-agent-architecture.md | Line 51 states "routing itself still relies on backstory wording, not this check" (S016). Line 15 of the **same page** states the rename made the read/write distinction reach "the router's `agent_name` field directly, not only its `backstory` prose" (S017), and agent-write-capability-routing.md's update note records the backstory-only approach as having failed in production | **Open** — this is a superseded claim, not a genuine source conflict, so no `> ⚠ conflict:` marker is warranted: S017 already supersedes S016 here and the wiki records that on agent-write-capability-routing.md. Narrow line 51 to what still holds — routing reads `agent_name` (S017) and is a separate mechanism from the dispatch guard — and re-cite it S016+S017 |
| 2 | stale | structural | mcp-integration.md, inbound-webhook-endpoint.md | Over the SCHEMA 600-word split rule, excluding frontmatter and Related: 620 and 619 words. Unchanged since 2026-08-14 | **Open** — each needs a topical split into a linked page pair. Four precedents now exist: inbound-event-queue.md → inbound-reply-metadata.md, teams-adapter.md → teams-reply-delivery.md, inbound-adapter-development.md → inbound-adapter-testing.md, agent-write-capability-routing.md → agent-write-step-guard.md |
| 3 | citations | semantic (low) | inbound-adapter-testing.md | "Everything downstream of `parse_events` runs for real" sits in a paragraph closing with (S021), but it characterizes the test setup rather than stating a claim S021 makes; S021 states only that external services are stubbed (Constitution I) | **Open** — either narrow it to what S021 supports, or verify it against `teams_adapter_test.rb` and cite that verification |

## Note on the previous pass

Finding 1 was reachable in the earlier pass today and was not reported: that
pass bounded the contradiction check to pages sharing S021/S022/S023 and never
compared the S016/S017 cluster. The stale clause itself dates from the
2026-08-07 ingest — it is not a regression introduced by the split. Bounding the
check is correct per the lint contract, but the bound must rotate across
clusters, not stay on the most recently ingested one.

## Verified, no finding

- **The split pair.** agent-write-capability-routing.md (364 words) and
  agent-write-step-guard.md (418) both sit well under the cap, link to each
  other, and divide the S016 claims without duplicating any: `can_write?` and
  router exposure on the first, the dispatch-time guard and its consequences on
  the second. S016's `Pages touched` was extended to match.
- **Seven pages citing S021 but dated 2026-08-14** (chat-history-apis.md,
  inbound-event-queue.md, inbound-reply-metadata.md, public-url-scope.md,
  teams-activity-mapping.md, teams-graph-history.md,
  teams-one-to-one-session-window.md) — checked against the revised S021 in the
  earlier pass; none is affected and none has changed since.
- **Watch list, at or near the cap**: teams-request-verification.md exactly 600,
  teams-adapter.md 593, inbound-adapter-development.md 585,
  inbound-chat-webhook-ingest.md 584. Each is one claim away from a split.

## Fixes applied

None. `auto_fix: index-and-links` had nothing to repair — the index and every
link were already consistent after the split. All three findings are semantic or
structural and are reported only, per the lint contract.
