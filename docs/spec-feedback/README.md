# Specification Feedback Log

This directory records corrections the user requested on AI-written specifications, together with an analysis of why the AI produced the original text.

## Purpose

AI-generated specifications often miss the author's intent and need correction. Each correction is recorded here so that the same kind of mistake is not repeated. Before writing or updating a specification, read the index below and the entries relevant to the feature.

## When to record

Record an entry when the user asks to correct an AI-written specification artifact and the correction is applied:

- `specs/` feature artifacts (`spec.md`, `plan.md`, `tasks.md`, `research.md`, `data-model.md`, contracts, etc.)
- Design documents written for a feature

Do **not** record:

- Typo fixes or pure wording changes that do not change meaning
- Changes the user makes for reasons unrelated to the AI output (e.g. the user changed requirements that were captured correctly)

When one correction request contains several points, combine the points that share a root cause into one entry and split points with different root causes into separate entries.

## Rules

- **Append-only**: never modify or delete past entries. If an entry turns out to be wrong, add a new entry that references and corrects it. The only edits allowed on existing files are adding rows to this README's index and, when an entry's prevention rule is promoted, updating that entry's **Promoted to** field and the matching index cell.
- **English only**: all entries must be written in English, even when the conversation was in another language. Quote the user's feedback as a faithful English translation.
- **Numbered sequentially**: use the format `NNN-short-title.md` (e.g., `001-assumed-default-permission.md`). If another branch merged an entry with the same number first, renumber yours (file name, heading, and index row) before merging.
- Use the `record-spec-feedback` skill to create entries.

## Root-cause categories

| Category | Meaning |
|----------|---------|
| `missing-context` | Information needed to write it correctly was not available to the AI (not in the request, specs, wiki, or code) |
| `unconfirmed-assumption` | The AI filled an ambiguous point with a guess instead of asking |
| `intent-misread` | The request was clear, but the AI interpreted it differently |
| `scope-creep` | The AI added requirements, behavior, or work that was not requested |
| `scope-gap` | The AI omitted something that was requested or clearly implied |
| `convention-unknown` | The AI did not follow an existing specification, behavior, or project convention it could have found |
| `granularity` | The level of detail was wrong (too detailed, too abstract, implementation details in the spec, etc.) |
| `other` | None of the above; explain in the entry and consider adding a new category |

Add a new category to this table when a recurring cause does not fit the existing ones.

## Template

```markdown
# SF-NNN: Title

**Date**: YYYY-MM-DD
**Feature**: specs/NNN-feature-name (branch `feature/NNN-...`)
**Artifact**: spec.md | plan.md | tasks.md | <other file>
**Category**: <category from the table>
**Related**: SF-NNN, ... (entries with the same pattern; "None" if none)

## Feedback

What the user pointed out (faithful English summary or translated quote).

## What the AI Wrote

The relevant part of the original output (excerpt or summary).

## Correction

How the artifact was changed.

## Root Cause

Why the AI produced the original text: what it relied on, what it should have
checked or asked, and why it did not.

## Prevention

A concrete, checkable rule to apply when writing future specifications.

**Promoted to**: AGENTS.md | constitution | <skill> | Not yet
```

## Index

| Entry | Title | Category | Feature | Promoted to |
|-------|-------|----------|---------|-------------|
| [SF-001](./001-assumed-azure-protocol.md) | Assumed Azure OpenAI keeps Chat Completions without asking | unconfirmed-assumption | 069-ruby-llm-2-1-migration | Not yet |
| [SF-002](./002-added-langfuse-token-breakdown.md) | Added Langfuse token breakdown fields not recorded today | scope-creep | 069-ruby-llm-2-1-migration | Not yet |
| [SF-003](./003-missed-leader-system-prompt.md) | Limited prompt reordering to the common agent prompt and missed the leader prompt | scope-gap | 070-prompt-caching | AGENTS.md |
| [SF-004](./004-citation-order-not-revisited-after-agent-decision.md) | Kept a citation order tied to the final answer after choosing a dedicated search agent | other | 071-web-search-citations | Not yet |
| [SF-005](./005-settings-contract-assumed-model-profile-present.md) | Settings contract dereferenced the main model profile without checking it can be unset | convention-unknown | 071-web-search-citations | Not yet |
| [SF-006](./006-web-search-contract-error-handling-scope.md) | Web search contract accepted cut-off answers and rescued every error in the agent | convention-unknown | 071-web-search-citations | Not yet |
| [SF-007](./007-excluded-discord-from-shared-removal.md) | Excluded Discord from a feature to restore a reaction removed from both chat adapters | scope-gap | 072-restore-slack-processing-reaction | AGENTS.md |
| [SF-008](./008-lifecycle-written-without-reading-gateway-queue.md) | Reaction lifecycle requirements written without reading the gateway queue and shutdown code | convention-unknown | 072-restore-slack-processing-reaction | AGENTS.md |
| [SF-009](./009-discord-error-code-claimed-from-docs-without-checking.md) | Discord reaction error claimed to come from the official docs without checking them | unconfirmed-assumption | 072-restore-slack-processing-reaction | AGENTS.md |
| [SF-010](./010-contract-prescribed-rescue-of-all-standard-errors.md) | Contract prescribed rescuing every StandardError from the adapter calls | convention-unknown | 073-chat-channel-progress | AGENTS.md |
| [SF-011](./011-failure-notice-included-in-markdown-formatting.md) | Included the failure notice in Slack Markdown formatting without reading its dedicated send path | convention-unknown | 074-slack-markdown-rendering | Not yet |
| [SF-012](./012-delivery-failure-notice-text-not-revisited.md) | Kept the "error while generating" notice for a new answer-delivery failure | scope-gap | 074-slack-markdown-rendering | Not yet |
| [SF-013](./013-edit-form-state-assumed-unaffected.md) | Assumed the edit-form state was unaffected by the clipping bug without measuring it | unconfirmed-assumption | 075-fix-health-report-clipping | Not yet |
| [SF-014](./014-fr-required-layout-not-expressible-in-css.md) | Required an exact "shrink to the remaining height" layout without checking that CSS can express it | unconfirmed-assumption | 075-fix-health-report-clipping | Not yet |
| [SF-015](./015-shared-renderer-fix-limited-to-one-screen.md) | Limited a fix in a shared Markdown renderer to one screen and froze the other callers | scope-gap | 076-fix-health-report-table-style | AGENTS.md |
| [SF-016](./016-alignment-kept-as-before-without-measuring.md) | Required table alignment to stay "as before" without measuring it in each view | unconfirmed-assumption | 076-fix-health-report-table-style | Not yet |
| [SF-017](./017-redmine-table-stripes-described-without-reading-css.md) | Described Redmine's table stripes from memory and required equal row colours everywhere | unconfirmed-assumption | 076-fix-health-report-table-style | AGENTS.md |
| [SF-018](./018-disabled-link-required-without-checking-redmine-css.md) | Required a visibly disabled link without checking that Redmine has a style for it | unconfirmed-assumption | 077-fix-dashboard-health-report-error | AGENTS.md |
| [SF-019](./019-streaming-placeholder-visibility-assumed.md) | Allowed raw chart directives to show during streaming without asking | unconfirmed-assumption | 078-health-report-charts | Not yet |
| [SF-020](./020-chart-form-chosen-for-implementation-ease.md) | Chose one chart form for every chart type for implementation ease without asking | unconfirmed-assumption | 078-health-report-charts | AGENTS.md |
| [SF-021](./021-chart-form-heuristic-applied-mechanically.md) | Applied a chart-form heuristic to every type without checking what each chart tells the reader | intent-misread | 078-health-report-charts | Not yet |
| [SF-022](./022-semantic-color-ignored-for-ordered-stages.md) | Assigned palette colors by position to stages that carry a meaning | unconfirmed-assumption | 078-health-report-charts | Not yet |
| [SF-023](./023-research-kept-doughnut-api-after-adr.md) | Research R-009 kept the doughnut drawing API after ADR-059 dropped donut charts | scope-gap | 078-health-report-charts | Not yet |
| [SF-024](./024-export-presentation-asked-per-element.md) | Asked about PDF presentation element by element instead of requiring the export to match the screen | intent-misread | 079-fix-health-report-pdf-table | Not yet |
| [SF-025](./025-pdf-styling-reinvented-instead-of-reusing-redmine-renderer.md) | Planned PDF styling tweaks and asked about them instead of reusing Redmine's own PDF renderer as-is | intent-misread | 079-fix-health-report-pdf-table | Not yet |
| [SF-026](./026-screen-match-read-as-style-match.md) | Read "match the screen" as matching styles and wrote a style-level user story | intent-misread | 079-fix-health-report-pdf-table | Not yet |
| [SF-027](./027-issue-decision-point-settled-without-asking.md) | Settled an issue's open decision point on embedded images without asking | unconfirmed-assumption | 080-office-attachment-markdown | Not yet |
| [SF-028](./028-empty-conversion-not-checked-against-notice-policy.md) | Kept sending an empty conversion result silently after choosing to report missing content | unconfirmed-assumption | 080-office-attachment-markdown | Not yet |
| [SF-029](./029-caller-audit-skipped-exception-handling.md) | Caller audit for a new exception checked return-value use but not the callers' rescues | scope-gap | 080-office-attachment-markdown | AGENTS.md |
| [SF-030](./030-research-dropped-fr-condition.md) | Research decision dropped the condition that the FR put on the UTF-8 repair | scope-gap | 080-office-attachment-markdown | Not yet |
| [SF-031](./031-file-path-put-in-exception-message.md) | Put the template file path in an exception message without checking where the message goes | convention-unknown | 081-fix-prompt-template-validation | Not yet |
