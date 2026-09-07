# Wiki Lint Report — 2026-09-07

Both findings from this pass were resolved by hand after reading source (not
lint auto-fixes — semantic findings are never auto-rewritten by lint itself).

| # | Check | Severity | Page | Finding | Outcome |
|---|-------|----------|------|---------|---------|
| 1 | contradictions | semantic | vector-search-internals.md | "Registration scope & project selection" (S033) said the multi-select "operates over" the widened base set, but the very next bullet (S012, unedited) said unconditionally that OFF "reveals a multi-select of module-enabled projects only." Read `app/controllers/ai_helper_settings_controller.rb:103` (`@vector_candidate_projects = @setting.vector_scope_projects.order(:name)`) and `app/models/ai_helper_setting.rb#vector_scope_projects` — confirmed the candidate list *does* widen to all non-archived projects when `all_projects_scope` is ON (also confirmed by `test/functional/ai_helper_settings_controller_test.rb:285-307`). Also caught along the way: the page claimed `vector_scope_projects` "returns `Project.all`" when ON — the code excludes archived projects. | Fixed: rewrote the "ON"/"OFF" bullets to name `@vector_candidate_projects` and condition the module-enabled-only claim on `all_projects_scope` being OFF (S033); corrected "`Project.all`" to "non-archived projects." |
| 2 | citations | semantic | mcp-listen-rejection.md | The "mcp 1.4.0 update" blockquote asserted a claim with no `S0xx` citation (only "(ADR-032)"); frontmatter `sources` omitted S030/S031 despite `sources.md` listing this page as touched by both. | Fixed: blockquote citation is now "(ADR-032, S030, S031)"; `S030, S031` added to frontmatter `sources`; `updated` bumped to 2026-09-07. |

## Checks with no findings

- **index-drift** — all 38 pages under `pages/` are listed in `INDEX.md`; the one duplicate-looking `mcp-server-endpoint.md` match is a legitimate inline cross-reference inside the `mcp-integration.md` index bullet, not a stray index line.
- **links** — no relative links (page-to-page or the two `../../docs/adr/*.md` references) point to a missing file.
- **orphans** — every page is linked from at least one other page.
- **citations (unknown ids)** — every `S0xx` citation used across `pages/*.md` resolves to a row in `sources.md`; no unknown source IDs.
- **stale** — all pages' `updated` dates are within 37 days (well under the 90-day `stale_after_days` threshold); for every page, the max `Last ingested` date among its cited sources is on or before the page's own `updated` date.

## Mechanical fixes applied

None needed — `INDEX.md` already matches `pages/` exactly and no links were broken or renamed.
