# Wiki Lint Report — 2026-10-03

All 3 findings were fixed by hand at the user's request (semantic findings are never auto-rewritten).

| # | Check | Severity | Page | Finding | Outcome |
|---|-------|----------|------|---------|---------------|
| 1 | contradictions | semantic | health-report.md | Unresolved `> ⚠ conflict:` — S011 says saved-report Markdown is parsed client-side by `AiHelperMarkdownParser`; S038 says saved reports were rendered with `textilizable` and now use server-side `md_to_html`. S038 describes the current code (feature 064), so the S011 claim is outdated. | Fixed: conflict marker removed; the page now states server-side `md_to_html` rendering (S038) and notes S011's client-side parsing as historical. |
| 2 | citations | semantic | mcp-server-endpoint.md | Body cites S027 and S029, but frontmatter `sources` omits them. | Fixed: S027, S029 added to `sources`. |
| 3 | citations | semantic | vector-search-internals.md | Body cites S002, but frontmatter `sources` omits it. | Fixed: S002 added to `sources`. |

## Checks with no findings

- **index-drift** — all 47 pages are in `INDEX.md`; no dangling entries.
- **links** — no broken relative links; all cited S-ids exist in `sources.md`.
- **orphans** — every page is linked from at least one other page.
- **stale** — no page older than 90 days; no source re-ingested after its pages were updated.
