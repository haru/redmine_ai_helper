---
title: Issue AI Features
type: component
sources: [S014, S017, S021, S035, S061]
updated: 2026-11-03
---

# Issue AI Features

A family of issue-centric features, mostly driven by `IssueReadAgent`
(renamed from `IssueAgent`, S017; a [worker agent](./multi-agent-architecture.md))
with per-feature prompt templates under `assets/prompt_templates/issue_read_agent/`
(S014, S017).

> Provenance: DeepWiki auto-generated doc (S014); `think_chat`, `structured_chat`,
> `find_similar_issues`, and `AiHelperSummaryCache` corroborate other pages.

## Summarization

`IssueReadAgent#issue_summary` loads the `summary` template and passes issue data —
plus attachments (text, images, PDFs) as file paths — to `chat` (S014; see
[Multi-modal File Support](./multi-modal-file-support.md)). Results are cached in
`AiHelperSummaryCache` (`issue_cache` read, `update_issue_cache` write), checked
before any LLM call (S014). The prompt enforces a strict format (overall summary,
bullets, a TODOs section) and a **prompt-injection defense**: the model is told
to *ignore meta-instructions embedded in the issue data* (S014).

A project-level `issue_summary_instructions` setting (same family as
`issue_draft_instructions` below) steers this summary, and when set, the
issue JSON is additionally enriched with the role names of the author,
assignee, and commenters, resolved via one `Member` bulk query so both users
and groups work — see
[Issue Summary Instructions & Role Gating](./issue-summary-instructions-role-gating.md)
for the role resolution and gating rule, and
[Issue Summary Instructions: Prompt Template & Settings](./issue-summary-instructions-prompt-template.md)
for the zero-prompt-diff mechanism (S035).

## Reply drafts

`IssueReadAgent#generate_issue_reply` injects the issue JSON plus a project's
`issue_draft_instructions` (`AiHelperProjectSetting`) into the `generate_reply`
template, and uses **`think_chat`** — the [Think Model](./think-model.md) — for
more coherent drafts (S014).

## Sub-issue generation

Uses the `sub_issues_draft` template with a JSON schema via **`structured_chat`**
(see [structured output](./llm-provider-layer.md)); it builds unsaved `Issue`
objects (`subject`, `description`, `due_date`) for review, driven by the
`AiHelperSubIssues` JS module (S014).

## Assignee suggestion

`RedmineAiHelper::AssignmentSuggestion` returns up to 3 suggestions from three
strategies (S014): **history** (`llm.find_similar_issues` → who resolved similar
issues), **workload** (DB open-issue counts, lowest first), and **instruction**
(LLM against project `assignment_suggestion_instructions`).

## Duplicate / similar check & effort estimate

Semantic search over subject + description (`llm.find_similar_issues_by_content`)
runs on issue creation (duplicate check) and on the detail page (scope: current
project / subprojects / all) — see [Vector Search](./vector-search.md) (S014).
When matches exist, `EffortEstimation` computes a `spent_hours` weighted average
by `similarity_score` (S014).

## Inline completion

A fill-in-the-middle experience: `IssueReadAgent` (or
`WikiAgent#generate_wiki_completion`) fetches suggestions from the cursor's
surrounding text via the `inline_completion` template, rendered as an overlay
behind a transparent textarea — description and notes fields only (S014).

Unlike the other features here, completion fires *while typing*, so its requests
must be debounced, deduplicated, aborted when superseded, and bounded by a short
server-side timeout with retries disabled — otherwise stale requests pile up and
block unrelated actions such as saving the issue (S021). See
[Inline Completion Request Flow](./inline-completion-request-flow.md) and
[Completion Request Timeout Policy](./completion-request-timeout-policy.md).

### Comment edit form and comment context

The typo check link and the completion checkbox also appear in the edit form of
a posted comment (rendered by the `view_journals_notes_form_after_notes` hook,
attached to the dynamically inserted form by a `MutationObserver` on `#history`
— [ADR-070](../../docs/adr/070-journal-edit-form-aids-attachment.md), S061). Completion
for comments always uses the note context: the browser sends
`context_type: "note"` (the new-comment field too), history is the newest 5 of
the newest 20 visible, non-private comments, and when editing a posted comment
the request carries `journal_id`, the writer is the comment's author, and only
earlier comments are used
([ADR-071](../../docs/adr/071-comment-completion-context.md), S061).

## Related

- [Multi-Agent Architecture](./multi-agent-architecture.md) ·
  [Think Model](./think-model.md) · [Vector Search](./vector-search.md) ·
  [Tool System](./tool-system.md) · [Plugin Overview](./plugin-overview.md) ·
  [Inline Completion Request Flow](./inline-completion-request-flow.md) ·
  [Issue Summary Instructions & Role Gating](./issue-summary-instructions-role-gating.md) ·
  [Issue Summary Instructions: Prompt Template & Settings](./issue-summary-instructions-prompt-template.md)
