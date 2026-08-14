# Wiki Lint Report — 2026-08-14

Scope: full pass over 32 pages, 22 sources.
Config: defaults (no `.specify/extensions/wiki/wiki-config.yml`) —
`stale_after_days: 90`, `require_citations: true`, `auto_fix: index-and-links`.

Findings 1–4 and 6 of this pass have since been fixed; finding 5 remains open.

## Check results

| Check | Result |
|---|---|
| index-drift | clean — 32/32 pages indexed, no dead index links, index grouping matches page frontmatter `type` |
| links | clean — 0 broken relative links; all cited IDs resolve to S001–S022 (`RS256` in teams-request-verification.md is not an S-id) |
| orphans | clean — every page has ≥1 inbound link from another page |
| contradictions | 4 findings, **all fixed** — no `> ⚠ conflict:` markers outstanding |
| stale | 1 finding, open — clean by date and by re-ingest; the finding is a schema page-size violation |
| citations | 1 finding, **fixed** — no uncited claims remain |

## Findings

| # | Check | Severity | Page | Finding | Resolution |
|---|-------|----------|------|---------|------------|
| 1 | contradictions | semantic | chat-history-apis.md | Intro said "**Both** return newest-first and are re-sorted to ascending by the adapter (S001)" while the page documents **three** platforms — and it was false for Teams: `teams_adapter.rb:587` sorts by `message["id"].to_i` rather than reversing a newest-first page as `slack_adapter.rb:294` / `discord_adapter.rb:705` do | **Fixed** — the intro now states all three hand the core ascending order, attributes the newest-first-then-reverse path to Slack/Discord (S001), and records that Graph's ordering is not relied on (S021) |
| 2 | contradictions | semantic | chat-channel-gateway-architecture.md | The "Structure" core list named only the five pre-044 files, omitting `inbound_adapter.rb` and `inbound_event_message.rb` — which the same page's "Inbound adapters" section and inbound-reply-metadata.md both treat as core — plus `gateway.rb` and `issue_link_formatter.rb` | **Fixed** — list completed, with the two inbound files attributed to 044-inbound-chat-webhook (S018) |
| 3 | citations | semantic | chat-channel-gateway-architecture.md | ADR-018 was named as the Teams design record but absent from `sources.md`; all Teams claims cited S021 (spec research/plan) while ADR-016 and ADR-017 each had their own ID | **Fixed** — ingested as **S022**; the four Teams decision pages now cite the accepted decision record |
| 4 | contradictions | semantic | chat-channel-gateway-architecture.md | Related-link gloss read "the **Slack/Discord** retrieval details", but that page now also documents Microsoft Graph | **Fixed** — gloss now reads Slack/Discord/Teams |
| 5 | stale | structural | agent-write-capability-routing.md, mcp-integration.md, inbound-webhook-endpoint.md | Over the SCHEMA 600-word split rule, excluding frontmatter and Related: 643, 620, 619 words | **Open** — each needs a topical split into a linked page pair, following the inbound-event-queue.md → inbound-reply-metadata.md and teams-adapter.md → teams-reply-delivery.md precedents |
| 6 | contradictions | semantic | 6 pages | "feature 044" was ambiguous: S018 is `specs/044-inbound-chat-webhook` and S021 is `specs/044-teams-chat-adapter`, both present on disk. teams-adapter.md used the bare number for the former while its own header meant the latter | **Fixed** — every bare mention across chat-channel-gateway-architecture.md, inbound-chat-webhook-ingest.md, inbound-adapter-development.md, public-url-scope.md, teams-adapter.md and inbound-webhook-endpoint.md now carries its slug |

## Verified as *not* findings

- `S256` in teams-request-verification.md — the JWT `RS256` algorithm, not a citation.
- `EventScopedHandler` (inbound-reply-metadata.md) — real, nested in `inbound_adapter.rb:86`.
- `reply_metadata_for` resolving by row id — matches `inbound_adapter.rb:139-147`, including the `thread_key` mismatch → `nil` behaviour.
- `docs/teams_gateway_setup.md`, `docs/adr/017`, `docs/adr/018`, `lib/.../adapters/teams_adapter.rb` — all exist as claimed.
- `RETENTION_DAYS = 7` is stated consistently by inbound-event-queue.md and teams-one-to-one-session-window.md.
