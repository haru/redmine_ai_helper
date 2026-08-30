# Wiki Lint Report — 2026-08-26

All 3 findings from the prior pass were fixed by hand (citation swaps, not
lint auto-fixes — semantic findings are never auto-rewritten).

| # | Check | Severity | Page | Finding | Outcome |
|---|-------|----------|------|---------|---------|
| 1 | citations | semantic | inline-completion-request-flow.md | "`ai_helper_logger` falls back to `Rails.logger`" was cited only as `(ADR-020)`, missing source ID **S022**. | Fixed: citation is now `(ADR-020, S022)`; `S022` added to frontmatter `sources`. |
| 2 | citations | semantic | completion-request-timeout-policy.md | "a timeout never locks completion where it happened" was cited only as `(ADR-021)`, missing source ID **S023**. | Fixed: citation is now `(ADR-021, S023)`; `S023` added to frontmatter `sources`. |
| 3 | citations | semantic | completion-suppression-scope.md | "ADR-021 folded it into `clearSuggestion`…" was cited only `(S021)`, missing source ID **S023**. | Fixed: citation is now `(S021, S023)`; `S023` added to frontmatter `sources`. |

Note: the original report's row 3 misquoted line 11 of this page as an
ADR-021 claim — it is actually about ADR-019 (a separate, still-uncited
decision not covered by S022/S023 and out of scope for this fix). Only the
genuine ADR-021/S023 gap on line 30 was corrected.

## Checks with no findings

- **index-drift** — all 35 pages under `pages/` are listed in `INDEX.md`; no dangling index entries.
- **links** — no relative links to missing pages across any page.
- **orphans** — every page is linked from at least one other page.
- **contradictions** — no unresolved `⚠ conflict` markers; spot-checked the highest-overlap source groups (S002, S016, S018, S021, S027/S028) for incompatible claims, none found.
- **stale** — all pages `updated` within the last 26 days (well under the 90-day `stale_after_days` threshold); no page's cited source has a `Last ingested` date newer than the page's own `updated` date.

## Mechanical fixes applied

None needed — `INDEX.md` already matched `pages/` exactly and no links were broken or renamed.
