# Code Review Feedback Log

This directory records code review findings on AI-generated code that led to a code change, together with an analysis of why the AI produced the original code.

## Purpose

AI-generated code often receives review findings that require fixes. Each adopted finding is recorded here so that the same kind of mistake is not repeated. Before generating code, read the index below and the entries relevant to the files or area you are about to change.

## When to record

Record an entry when a finding from one of the following reviews leads to a code change:

- GitHub Copilot review on a pull request
- A local AI review (e.g. `/code-review`, `speckit-review-*` skills)

Do **not** record:

- Findings that were not adopted (no code change)
- Typo fixes or pure formatting changes

When one review contains several findings, combine the findings that share a root cause into one entry and split findings with different root causes into separate entries.

## Rules

- **Append-only**: never modify or delete past entries. If an entry turns out to be wrong, add a new entry that references and corrects it. The only edits allowed on existing files are adding rows to this README's index and, when an entry's prevention rule is promoted, updating that entry's **Promoted to** field and the matching index cell.
- **English only**: all entries must be written in English.
- **Numbered sequentially**: use the format `NNN-short-title.md` (e.g., `001-n-plus-one-in-version-list.md`). If another branch merged an entry with the same number first, renumber yours (file name, heading, and index row) before merging.
- Use the `record-code-review-feedback` skill to create entries.

## Root-cause categories

| Category | Meaning |
|----------|---------|
| `convention-violation` | The code broke a rule in AGENTS.md, the constitution, an ADR, or an established project pattern |
| `error-handling` | Wrong error handling (silent fallback, wrong error type, missing handling) |
| `security` | Security issue (XSS, injection, secret exposure, etc.) |
| `permission` | Missing or wrong Redmine permission / visibility check |
| `edge-case` | An input or state the code did not handle (nil, empty, boundary) |
| `performance` | Inefficient code (N+1 queries, unnecessary loading) |
| `test-gap` | Missing, weak, or environment-dependent tests |
| `readability` | Naming, duplication, unnecessary complexity |
| `doc-comment` | Inaccurate or missing comments / YARD docs |
| `other` | None of the above; explain in the entry and consider adding a new category |

Add a new category to this table when a recurring cause does not fit the existing ones.

## Template

```markdown
# CRF-NNN: Title

**Date**: YYYY-MM-DD
**Source**: GitHub Copilot (PR #NNN) | Local AI review (<skill or command>)
**Feature**: branch `feature/NNN-...` / PR #NNN
**Files**: path/to/file.rb, ...
**Category**: <category from the table>
**Related**: CRF-NNN, ... (entries with the same pattern; "None" if none)

## Feedback

What the reviewer pointed out (summary, with a link to the review comment if available).

## Original Code

The relevant excerpt of the code before the fix.

## Fix

How the code was changed (excerpt or summary, commit hash if available).

## Root Cause

Why the AI generated the original code: what it relied on, what it should have
checked, and why it did not.

## Prevention

A concrete, checkable rule to apply when generating future code.

**Promoted to**: AGENTS.md | constitution | ADR-NNN | <skill> | Not yet
```

## Index

| Entry | Title | Category | Source | Promoted to |
|-------|-------|----------|--------|-------------|
| [CRF-001](./001-azure-embed-provider-slug.md) | Azure embedding still used the :openai provider after the :azure migration | edge-case | Local AI review | Not yet |
| [CRF-002](./002-secrets-in-rejected-config-log.md) | Rejected MCP server config was logged in full, including credentials | security | Local AI review | Not yet |
| [CRF-003](./003-swallowed-mcp-and-structured-output-errors.md) | Errors swallowed or cached as empty results around MCP tools and structured output | error-handling | Local AI review | AGENTS.md |
| [CRF-004](./004-end-user-dropped-by-responses-protocol.md) | Spec-assumed with_end_user does not send the user ID on the OpenAI Responses protocol | other | Local AI review | Not yet |
| [CRF-005](./005-stale-dead-code-and-docs-after-migration.md) | Dead branches, stale comments and tests tied to the old API left after the RubyLLM 2.1 migration | doc-comment | Local AI review | AGENTS.md |
| [CRF-006](./006-untested-paused-chat-guard.md) | Paused-chat guard added without a test that exercises it | test-gap | GitHub Copilot (PR #499) | AGENTS.md |
| [CRF-007](./007-docs-not-updated-after-review-fix.md) | Docs kept describing behaviour that a review fix had changed | doc-comment | GitHub Copilot (PR #499) | AGENTS.md |
| [CRF-008](./008-leader-lead-in-sentence-dropped.md) | Leader prompt lead-in sentence dropped when splitting the template | convention-violation | Local AI review | Not yet |
| [CRF-009](./009-unvalidated-instructions-value-object.md) | Instructions value object and apply_instructions accepted invalid input silently | error-handling | Local AI review | AGENTS.md |
| [CRF-010](./010-prompt-caching-test-gaps.md) | Prompt caching tests missed cache stability, explicit profiles and the end-to-end payload | test-gap | Local AI review | AGENTS.md |
| [CRF-011](./011-cache-docs-overstated-behaviour.md) | Prompt caching docs and comments described behaviour more narrowly or strongly than the code | doc-comment | Local AI review | AGENTS.md |
| [CRF-012](./012-prompt-caching-simplifications.md) | Hand-written branching where a single path or data mapping suffices | readability | Local AI review | Not yet |
| [CRF-013](./013-settings-view-nil-model-profile.md) | Settings page crashed when web search was on and no main model profile was set | edge-case | Local AI review | Not yet |
| [CRF-014](./014-web-search-truncated-answer-and-broad-rescue.md) | Truncated web search answers counted as success, and the rescue hid plugin errors | error-handling | Local AI review | Not yet |
| [CRF-015](./015-citation-type-invariant-gaps.md) | Web citation types left invariants unenforced at their edges | convention-violation | Local AI review | Not yet |
| [CRF-016](./016-web-search-docs-overstated-support.md) | Web search docs overstated OpenAI support and omitted the Think-model case | doc-comment | Local AI review | Not yet |
| [CRF-017](./017-web-search-test-gaps.md) | Web search tests skipped the negative routing path, read-only mode and the real payload | test-gap | Local AI review | Not yet |
| [CRF-018](./018-web-search-simplifications.md) | Repeated expressions and a dead initial value in the web search change | readability | Local AI review | Not yet |
| [CRF-019](./019-regex-html-stripping-in-test.md) | Test stripped script blocks from HTML with a regular expression | test-gap | GitHub CodeQL (PR #505) | Not yet |
| [CRF-020](./020-shutdown-race-widened-by-reaction-call.md) | A slow reaction call between the shutdown check and the queue push lost messages | edge-case | Local AI review | Not yet |
| [CRF-021](./021-discord-unknown-emoji-ignored-as-missing-reaction.md) | Discord "Unknown Emoji" error ignored as if it meant a missing reaction | error-handling | Local AI review | Not yet |
| [CRF-022](./022-progress-rescue-too-broad.md) | Progress reporter rescued every StandardError from the adapter and trusted its return value | error-handling | Local AI review | AGENTS.md |
| [CRF-023](./023-progress-docs-inaccurate.md) | Progress docs described the plan line, the no-step case and permissions inaccurately | doc-comment | Local AI review | Not yet |
| [CRF-024](./024-progress-test-gaps.md) | Progress tests could not fail or did not confirm the failure they simulated | test-gap | Local AI review | Not yet |
| [CRF-025](./025-progress-docs-claims-corrected.md) | Progress docs and a test claimed behaviour the code does not have | doc-comment | User review | Not yet |
| [CRF-026](./026-blank-slack-markdown-body.md) | Slack markdown body guard let blank and non-String text through | edge-case | Local AI review | Not yet |
| [CRF-027](./027-delivery-failure-reported-as-generation-failure.md) | Answer delivery failure reported to the user as a generation failure | error-handling | Local AI review | Not yet |
| [CRF-028](./028-slack-markdown-docs-overstated.md) | Plain-notice docs overstated the formatting, and a wiki link was broken | doc-comment | Local AI review | Not yet |
| [CRF-029](./029-slack-markdown-test-gaps.md) | Slack markdown tests skipped the progress payload end to end and compared JSON strings | test-gap | Local AI review | Not yet |
| [CRF-030](./030-mutable-unvalidated-link-format.md) | IssueLinkFormatter::Format was a mutable Struct without validation | convention-violation | Local AI review | Not yet |
| [CRF-031](./031-duplicated-slack-chunk-posting.md) | Slack rich and plain senders duplicated the chunk-posting loop | readability | Local AI review | Not yet |
| [CRF-032](./032-adr-cause-diverged-from-research.md) | ADR and CSS comments described a cause and alternatives that research did not record | doc-comment | Local AI review | AGENTS.md |
| [CRF-033](./033-css-scanner-test-silent-misparse.md) | CSS source-scan test misparsed unsupported constructs silently and had bypassable negative checks | test-gap | Local AI review | AGENTS.md |
| [CRF-034](./034-layout-css-test-duplication.md) | Layout CSS test re-parsed the stylesheet per lookup and duplicated selector constants | readability | Local AI review | Not yet |
| [CRF-035](./035-environment-dependent-and-vacuous-table-tests.md) | Table class tests pinned Redmine-version markup, matched the wrong element and had narrow negative checks | test-gap | Local AI review | Not yet |
| [CRF-036](./036-parser-guard-skipped-unrelated-init.md) | Early return for a missing Markdown parser silently skipped initialization that no longer needed it | error-handling | Local AI review | Not yet |
| [CRF-037](./037-adr-misattributed-quote-and-stale-comments.md) | ADR quoted a decision from the wrong source; comments and promotion fields were inaccurate | doc-comment | Local AI review | Not yet |
| [CRF-038](./038-streaming-parser-dropped-explicit-left-alignment.md) | Streaming Markdown parser dropped explicit left alignment, breaking RTL parity with the server renderer | edge-case | GitHub Copilot (PR #525) | Not yet |
| [CRF-039](./039-adr-called-streaming-display-server-rendered.md) | ADR listed the browser-rendered streaming display among server-rendered tables | doc-comment | GitHub Copilot (PR #525) | Not yet |
| [CRF-040](./040-generation-cleanup-left-edit-view-hidden.md) | Generation cleanup un-hid the result area but not the view that startEdit had hidden | edge-case | Local AI review | Not yet |
| [CRF-041](./041-finalize-mutated-dom-before-guard.md) | Finalize mutated the DOM before the guard that could reject it | error-handling | Local AI review | Not yet |
| [CRF-042](./042-test-dom-derived-from-code-not-erb.md) | Test DOM and assertions were derived from the code instead of the real markup | test-gap | Local AI review | Not yet |
| [CRF-043](./043-comments-described-narrower-scopes.md) | Comments described narrower scopes than the code they annotate | doc-comment | Local AI review | Not yet |
| [CRF-044](./044-promoted-feedback-rules-narrowed.md) | Promoted feedback rules were narrowed, half-dropped and mis-cited | doc-comment | Local AI review | Not yet |
| [CRF-045](./045-finalize-accepted-detached-pane.md) | Finalize accepted a result area detached together with its whole pane | edge-case | GitHub Copilot (PR #526) | Not yet |
| [CRF-046](./046-sse-try-wrapped-data-read.md) | SSE try block wrapped reading the event data, not only the parse | error-handling | GitHub Copilot (PR #526) | Not yet |
| [CRF-047](./047-client-swap-failures-unhandled.md) | Saved-report swap and chart loading failed silently in the browser | error-handling | Local AI review | Not yet |
| [CRF-048](./048-redmine-version-matrix-chart-loading.md) | Chart.js loading ignored Redmine 6.0 (no importmap) and the overview page | edge-case | Local AI review | Not yet |
| [CRF-049](./049-dom-and-index-boundaries.md) | Observer-added export links, observer root node and index 0 boundaries were missed | edge-case | Local AI review | Not yet |
| [CRF-050](./050-value-object-and-union-checks-incomplete.md) | New chart value objects and Chart\|Unavailable results skipped the CRF-003/CRF-009 checks | convention-violation | Local AI review | AGENTS.md |
| [CRF-051](./051-chart-tests-vacuous-or-one-sided.md) | Chart tests passed without the guard, diverged between Ruby and JS, and skipped call sites | test-gap | Local AI review | AGENTS.md |
| [CRF-052](./052-chart-comments-described-other-behaviour.md) | Chart comments and docs described behaviour the code does not have | doc-comment | Local AI review | Not yet |
| [CRF-053](./053-html-block-directives-caused-500.md) | Directives inside CommonMark HTML blocks made every report render fail with HTTP 500 | edge-case | Local AI review | Not yet |
| [CRF-054](./054-stream-and-chart-failures-swallowed.md) | Stream completion, swap and chart failures were swallowed or invisible in the browser and the controller | error-handling | Local AI review | Not yet |
| [CRF-055](./055-union-and-value-object-checks-missed-again.md) | Union returns and late-added value objects skipped the case/else and invariant checks again | convention-violation | Local AI review | Not yet |
| [CRF-056](./056-chart-heads-only-in-one-erb-branch.md) | Chart heads were loaded only in the saved-report branch of the overview partial | edge-case | Local AI review | Not yet |
| [CRF-057](./057-guard-and-sse-contract-test-gaps.md) | Resolver guards were unreachable from tests and the SSE contract was tested only through stubs | test-gap | Local AI review | Not yet |
| [CRF-058](./058-doughnut-era-and-pre-swap-docs-survived.md) | Doughnut-era and pre-swap docs survived in specs, wiki and comments | doc-comment | Local AI review | Not yet |
