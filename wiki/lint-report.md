# Wiki Lint Report — 2026-08-08 (second pass)

Scope: full pass. 25 pages, 20 sources. Auto-fix mode: `index-and-links`.
Supersedes the earlier 2026-08-08 report, whose finding 1 is now **resolved**.

## Results per check

| Check | Result |
|-------|--------|
| index-drift | ✅ clean — all 25 pages appear in `INDEX.md` under the group matching their frontmatter `type`; no index line points at a missing file |
| links | ✅ clean — every `./*.md` relative link resolves (pages + INDEX); every `(Sxxx)` citation names a registered source (S001–S020) |
| orphans | ✅ clean — every page has ≥1 inbound link from another page. The five feature-044 pages form a connected cluster reachable from `chat-channel-gateway-architecture.md` |
| contradictions | ✅ clean — **no `⚠ conflict:` markers remain**. The S002-vs-S018 public-URL conflict was resolved by ingesting ADR-017 (S019): S002's claim now stands scoped to outbound adapters, with the amendment cited to S019 on [Public URL Scope](./pages/public-url-scope.md) |
| stale | ✅ clean — oldest page is `updated: 2026-08-01`, far inside the 90-day threshold (2026-05-10); no source's `Last ingested` postdates a page citing it |
| citations | ⚠ 1 finding — one uncited aside, now unchanged across four passes |
| *(page size — SCHEMA rule, not a listed check)* | ⚠ 1 finding — 7 pages exceed the 600-word split rule, up from 4 |

## Findings

| # | Check | Severity | Page | Finding | Suggested fix |
|---|-------|----------|------|---------|---------------|
| 1 | page-size | structural | inbound-event-queue.md (702), inbound-webhook-endpoint.md (699), agent-write-capability-routing.md (693), mcp-integration.md (671), inbound-chat-webhook-ingest.md (663), chat-channel-gateway-architecture.md (628), vector-search.md (617) | `SCHEMA.md` requires splitting a page past 600 words. 7 of 25 pages now exceed it — the three feature-044 pages joined the list during the S018–S020 ingests, after prose trimming failed to bring them under. Roughly 30–45 words of each inbound page's count is table markup rather than prose, so the true overrun is ~10%. | Judgment call, not mechanical: either accept the overrun (all seven are coherent single topics, and feature 044 already spans five pages) or raise `ingest.page_max_words` in a project `wiki-config.yml` to match how these pages are actually written. Splitting further would scatter one mechanism across two files. Not auto-fixable. |
| 2 | citations | low | mcp-integration.md:38–39 | The aside "the project also refers to these as `SubMcpAgent` classes" carries no source ID. It reconciles S006 (which named the class `AiHelperMcpSlack`) with the project's `CLAUDE.md`, and belongs to no registered source. **Unchanged across four consecutive lint passes.** | Register `CLAUDE.md` as a source and cite it, or reframe the aside as a `> Provenance:` note (the convention already used on the architecture/tool/provider pages). Not auto-fixable — semantic. |

## Fixes applied

None. `INDEX.md` and every link target were already consistent — nothing mechanical to repair.

## Notes

*Observations, not defects — no action required.*

- **Two registration mechanisms, described separately.** `chat-channel-gateway-architecture.md`
  says adapters register via the `inherited` hook (S001);
  `inbound-adapter-development.md` says an adapter file is picked up by the
  `Dir[…adapters/*_adapter.rb]` glob in `init.rb` (S020). These are
  complementary halves of one flow (the glob loads the file, the hook registers
  the class), not a contradiction — but neither page mentions the other half.
  Ingesting `init.rb` or `base_adapter.rb` would let one page state it whole.
- **Feature 044 coverage is now three-source deep.** Its five pages rest on
  S018 (design intent), S019 (the accepted ADR) and S020 (the shipped
  developer guide), the strongest corroboration in the wiki. The remaining
  unregistered artifacts are the two contract files under
  `specs/044-inbound-chat-webhook/contracts/`, which S020 names as the
  method-level authority.
- **Source mix.** 8 of 20 sources are DeepWiki (AI-generated); the other 12 are
  7 spec/feature artifacts, the README, 2 ADRs and 2 project docs. The last
  five ingests were all first-party, so the DeepWiki share keeps falling.
  Tracked as a confidence signal, not a defect.
