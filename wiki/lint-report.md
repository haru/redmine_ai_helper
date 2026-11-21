# Wiki Lint Report — 2026-11-21

Mechanical fixes applied: none needed (`index-drift` and `links` are clean). Row 1 was fixed by hand afterwards at the user's request; the other findings are reported only.

| # | Check | Severity | Page | Finding | Suggested fix |
|---|-------|----------|------|---------|---------------|
| 1 | orphans | structural | project-management-tools.md | No other page links to it (only `INDEX.md`). | Fixed: linked from the Related list in `tool-system.md`. |
| 2 | stale | semantic | nginx-sse-proxy.md, custom-commands.md, chat-history-apis.md, chat-context-import.md, discord-message-content-intent.md, think-model.md (all updated 2026-08-01) | `updated` is older than 90 days. No source for them was re-ingested later. | Check against the current code and re-ingest the source, or touch `updated` after verifying. |
| 3 | stale | semantic | inbound-chat-webhook-ingest.md, inbound-webhook-endpoint.md, inbound-event-queue.md, inbound-adapter-development.md, public-url-scope.md (2026-08-07 to 2026-08-08), agent-write-capability-routing.md (2026-08-07) | Same: older than 90 days. | Same as #2. |
| 4 | stale | semantic | classic-script-testing-strategy.md, js-coverage-ratchet-policy.md, js-quality-tooling.md, js-test-convention.md (all 2026-08-22) | Same, and they are at the edge: older than 90 days as of 2026-11-21. | Re-verify against `vitest.config.js` and `package.json`. |
| 5 | citations | structural | (18 pages over 600 words) | Exceeded the 600-word split rule in `SCHEMA.md`. | Fixed: all 18 split into a main page plus a linked sub-page (all now under 600 words); each split is listed in `INDEX.md`. |

## Checks with no findings

- **index-drift** — all pages are in `INDEX.md`; no dangling entries.
- **links** — no broken relative links; all cited S-ids exist in `sources.md`.
- **contradictions** — no `> ⚠ conflict:` markers.
