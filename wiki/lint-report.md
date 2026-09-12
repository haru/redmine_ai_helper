# Wiki Lint Report — 2026-09-12

All 4 findings from the prior pass were fixed (semantic fixes applied by hand —
semantic findings are never auto-rewritten).

| # | Check | Severity | Page | Finding | Outcome |
|---|-------|----------|------|---------|---------|
| 1 | contradictions | semantic | all-projects-data-access-scope.md | The section "`data_access_condition` callers must already scope visibility" stated "The SQL condition alone does not check row visibility", contradicting ADR-036 ("deliberately self-contained: it always ANDs `Project.visible_condition(user)` with the module/scope part") and the current `permission_checker.rb:63-73`. | Fixed: section rewritten to say the condition is self-contained and that callers applying `Issue.visible(user)` simply AND the constraint twice (harmless). |
| 2 | stale | semantic | all-projects-data-access-scope.md | The `data_access_condition` code block omitted the `"(#{Project.visible_condition(user)}) AND (...)"` wrapper that the shipped method has, so the quoted code no longer matched the source. | Fixed: snippet replaced with the current implementation, including the visibility wrapper. |
| 3 | stale | semantic | all-projects-scope-effects.md | "Recorded as ADR-036 (planned; not yet merged as of this ingest)" — ADR-036 is merged and Accepted, and its scope is now amended by ADR-037. | Fixed: now references ADR-036 as Accepted, amended by ADR-037. |
| 4 | stale | semantic | INDEX.md | The hook for All-Projects Data-Access Scope still said the methods "centralize 8 duplicated module-gated checks"; after S034 every data-reaching tool consults them, not just those eight sites. | Fixed: hook reworded to describe the whole-tool-surface enforcement (the original 8 sites noted as history). |

## Checks with no findings

- **index-drift** — all 39 pages under `pages/` are listed in `INDEX.md`; no dangling index entries.
- **links** — no relative links to missing pages across any page; all cited source IDs are known.
- **orphans** — every page is linked from at least one other page.
- **citations** — all claims added in the S034 pass carry a source ID.
