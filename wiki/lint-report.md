# Wiki Lint Report — 2026-08-01

Scope: full pass. 19 pages, 14 sources. Auto-fix mode: `index-and-links`.

## Results per check

| Check | Result |
|-------|--------|
| index-drift | ✅ clean — all 19 pages listed in `INDEX.md`; no index line points at a missing file |
| links | ✅ clean — every `./*.md` relative link resolves; every `(Sxxx)` citation names a registered source (S001–S014) |
| orphans | ✅ clean — every page has ≥1 inbound link (minimums: chat-sidebar, issue-ai-features, vector-search-internals — each reachable from a hub page) |
| contradictions | ✅ clean — no unresolved `⚠ conflict:` markers. Cross-source claims checked in the high-overlap areas (Anthropic S002↔S004, read-only mode across tool-system/mcp/architecture/sidebar, `messages_for_openai`, `AiHelperMarkdownParser`, `think_chat`) are mutually consistent |
| stale | ✅ clean — all pages `updated: 2026-08-01`; nothing past the 90-day threshold (2026-05-03); no source re-ingested after its page's last update |
| citations | ⚠ 1 low-severity finding (repeat from prior report) |

## Findings

| # | Check | Severity | Page | Finding | Suggested fix |
|---|-------|----------|------|---------|---------------|
| 1 | citations | low | mcp-integration.md:39 | The aside "the project also refers to these as `SubMcpAgent` classes" carries no source ID. It is an editorial reconciliation between S006 (which named the class `AiHelperMcpSlack`) and the project's CLAUDE.md, not a claim from any registered source. **Unchanged since the last lint.** | Reframe as a `> Provenance:` note (as on the architecture/tool/provider pages), or register the plugin's `CLAUDE.md` as a source and cite it. No auto-fix (semantic). |

## Fixes applied

None. `INDEX.md` and all link targets were already consistent — nothing mechanical to repair.

## Note on source mix

8 of 14 sources are DeepWiki (AI-generated); the rest are 5 specs + the README.
Several DeepWiki-only claims have since gained spec/README corroboration
(MCP, provider layer, vector rake tasks, health report, chat sidebar names). No
action required — tracked here as a confidence signal, not a defect.
