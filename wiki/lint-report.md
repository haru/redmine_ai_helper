# Wiki Lint Report — 2026-09-12

| # | Check | Severity | Page | Finding | Suggested fix |
|---|-------|----------|------|---------|---------------|
| 1 | contradictions | semantic | all-projects-data-access-scope.md | The section "`data_access_condition` callers must already scope visibility" states "The SQL condition alone does not check row visibility", contradicting ADR-036 ("deliberately self-contained: it always ANDs `Project.visible_condition(user)` with the module/scope part") and the current `permission_checker.rb:63-73`. Pre-existing; not introduced by the S034 ingest. | Rewrite the section to say the condition is self-contained, and that callers applying `Issue.visible(user)` simply AND the constraint twice (harmless). |
| 2 | stale | semantic | all-projects-data-access-scope.md | The `data_access_condition` code block (lines 43-49) omits the `"(#{Project.visible_condition(user)}) AND (...)"` wrapper that the shipped method has, so the quoted code no longer matches the source. Pre-existing. | Replace the snippet with the current implementation. |
| 3 | stale | semantic | all-projects-scope-effects.md | "Recorded as ADR-036 (planned; not yet merged as of this ingest)" — ADR-036 is merged and Accepted, and its scope is now amended by ADR-037. Pre-existing. | Replace with a reference to ADR-036 as Accepted, amended by ADR-037. |
| 4 | stale | semantic | INDEX.md | The hook for All-Projects Data-Access Scope still says the methods "centralize 8 duplicated module-gated checks"; after S034 every data-reaching tool consults them, not just those eight sites. | Reword the hook to describe the whole-tool-surface enforcement. |
| 5 | index-drift | mechanical | — | No findings (39 pages, 39 indexed). | — |
| 6 | links | mechanical | — | No findings (no broken relative links, no unknown source IDs). | — |
| 7 | orphans | structural | — | No findings (every page has at least one inbound page link). | — |
| 8 | citations | semantic | — | No findings: all claims added in the S034 pass carry a source ID. | — |
