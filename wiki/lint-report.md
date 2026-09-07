# Wiki Lint Report — 2026-09-07

| # | Check | Severity | Page | Finding | Suggested fix |
|---|-------|----------|------|---------|---------------|
| 1 | contradictions | semantic | vector-search-internals.md | "Registration scope & project selection" (S033) says the "Register all projects" / per-project-selection behavior "operates over that widened base set" once `all_projects_scope` is ON, but the very next bullet (S012, unedited) states unconditionally that "OFF reveals a multi-select of **module-enabled projects only**" — no qualifier for the widened case. Cross-checking [all-projects-scope-effects.md](./pages/all-projects-scope-effects.md), which says the settings controller adds a separate `@vector_candidate_projects` for the vector tab (implying the candidate pool *does* widen), the S012 bullet block reads as stale relative to the S033 addition above it. | Clarify whether the OFF-state multi-select candidate list includes module-disabled projects when `all_projects_scope` is ON; if so, add an S033-cited qualifier to the bullet instead of leaving the S012 wording unconditional. |
| 2 | citations | semantic | mcp-listen-rejection.md | The "mcp 1.4.0 update" blockquote (lines 15–19) asserts a synthesized claim ("part 2 of the fix... was later deleted to fix a regression...") with no source-ID citation — only "(ADR-032)", a document reference, not an `S0xx` id. Frontmatter `sources: [S027, S028, S029]` also omits S030/S031, even though `sources.md` lists this page as touched by both. | Add `(S030, S031)` to the blockquote's claim; add `S030, S031` to the page's frontmatter `sources` list. |

## Checks with no findings

- **index-drift** — all 38 pages under `pages/` are listed in `INDEX.md`; the one duplicate-looking `mcp-server-endpoint.md` match is a legitimate inline cross-reference inside the `mcp-integration.md` index bullet, not a stray index line.
- **links** — no relative links (page-to-page or the two `../../docs/adr/*.md` references) point to a missing file.
- **orphans** — every page is linked from at least one other page.
- **citations (unknown ids)** — every `S0xx` citation used across `pages/*.md` resolves to a row in `sources.md`; no unknown source IDs.
- **stale** — all pages' `updated` dates are within 37 days (well under the 90-day `stale_after_days` threshold); for every page, the max `Last ingested` date among its cited sources is on or before the page's own `updated` date — no page trails a re-ingested source, aside from finding #2 above (a missing citation, not a date-staleness case).

## Mechanical fixes applied

None needed — `INDEX.md` already matches `pages/` exactly and no links were broken or renamed.
