# Wiki Lint Report — 2026-08-14

Scope: full pass over 31 pages, 21 sources.
Config: defaults (no `.specify/extensions/wiki/wiki-config.yml`) —
`stale_after_days: 90`, `require_citations: true`, `auto_fix: index-and-links`.

## Check results

| Check | Result |
|---|---|
| index-drift | clean — 31/31 pages indexed, no dead index links, every index grouping matches page frontmatter `type` |
| links | clean — 0 broken relative links; all cited IDs resolve to S001–S021 (`RS256` in teams-request-verification.md is not an S-id) |
| orphans | clean — every page has ≥1 inbound link from another page (lowest: chat-sidebar.md, issue-ai-features.md, vector-search-internals.md at 1) |
| contradictions | 3 findings — no `> ⚠ conflict:` markers outstanding; findings are pairwise drift in the S021 cluster |
| stale | clean by date (oldest page 2026-08-01, 13 days) and by re-ingest (no page older than a source it cites) |
| citations | clean — no uncited claims; every table and bullet list sits under a cited lead-in |

Mechanical fixes applied: **0** (nothing to fix). Semantic findings: **5**, all
reported only.

## Findings

| # | Check | Severity | Page | Finding | Suggested fix |
|---|-------|----------|------|---------|---------------|
| 1 | contradictions | semantic | chat-history-apis.md | Intro says "**Both** return newest-first and are re-sorted to ascending by the adapter (S001)" while the page documents **three** platforms. False for Teams: `teams_adapter.rb:587` sorts by `message["id"].to_i`, it does not reverse a newest-first payload the way `slack_adapter.rb:294` / `discord_adapter.rb:705` do | Rewrite the sentence to scope the newest-first claim to Slack and Discord, and state Teams' ordering (sorted by numeric message id) in the Teams section |
| 2 | contradictions | semantic | chat-channel-gateway-architecture.md | The "Structure" core list — `context_importer.rb, message_handler.rb, incoming_message.rb, history_message.rb, base_adapter.rb` (S001) — omits `inbound_adapter.rb` and `inbound_event_message.rb`, which the **same page's** "Inbound adapters" section and inbound-reply-metadata.md both treat as core (`InboundEventMessage < IncomingMessage`, `EventScopedHandler < MessageHandler`). `gateway.rb` and `issue_link_formatter.rb` are also missing | Extend the core list with the S018/S021-era files and cite S018/S021 alongside S001 |
| 3 | citations | semantic | chat-channel-gateway-architecture.md | The page names **ADR-018** (`docs/adr/018-teams-inbound-adapter-design.md`, present on disk) as the Teams design record, but ADR-018 is absent from `sources.md`; every Teams claim is attributed to S021 (spec research/plan). ADR-016 and ADR-017 each got their own ID (S017, S019) | `/speckit.wiki.ingest docs/adr/018-teams-inbound-adapter-design.md` — registers S022 and lets the Teams decision pages cite the accepted decision rather than the plan |
| 4 | contradictions | semantic | chat-channel-gateway-architecture.md | Related-link gloss reads "[Chat History APIs] — the **Slack/Discord** retrieval details behind the fetch methods", but that page now also documents Microsoft Graph, and this page's own capability section says "Slack, Discord and Teams all override these to `true`" | Update the gloss to "the Slack/Discord/Teams retrieval details" |
| 5 | stale | structural | agent-write-capability-routing.md, mcp-integration.md, inbound-webhook-endpoint.md | Over the SCHEMA 600-word split rule, excluding frontmatter and the Related section: 643, 620, 620 words. (inbound-event-queue.md was already split this way into inbound-reply-metadata.md) | Split each into a page pair that links both ways, following the inbound-event-queue.md → inbound-reply-metadata.md precedent |
| 6 | contradictions | semantic | teams-adapter.md, inbound-adapter-development.md | "feature 044" is ambiguous: S018 is `specs/044-inbound-chat-webhook` and S021 is `specs/044-teams-chat-adapter` — two different features share the number, and both dirs exist. teams-adapter.md's "the feature 044 webhook foundation" means the former; its own header means the latter | Qualify each mention with the slug (`044-inbound-chat-webhook` vs `044-teams-chat-adapter`) |

## Verified as *not* findings

- `S256` in teams-request-verification.md — the JWT `RS256` algorithm, not a citation.
- `EventScopedHandler` (inbound-reply-metadata.md) — real, nested in `inbound_adapter.rb:86`.
- `reply_metadata_for` resolving by row id (inbound-reply-metadata.md, inbound-event-queue.md) — matches `inbound_adapter.rb:139-147`, including the `thread_key` mismatch → `nil` behaviour.
- `docs/teams_gateway_setup.md`, `docs/adr/017`, `docs/adr/018`, `lib/.../adapters/teams_adapter.rb` — all exist as claimed.
- `RETENTION_DAYS = 7` is stated consistently by inbound-event-queue.md and teams-one-to-one-session-window.md.
