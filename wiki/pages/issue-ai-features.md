---
title: Issue AI Features
type: component
sources: [S014, S017, S021]
updated: 2026-08-20
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

## Related

- [Multi-Agent Architecture](./multi-agent-architecture.md) ·
  [Think Model](./think-model.md) · [Vector Search](./vector-search.md) ·
  [Tool System](./tool-system.md) · [Plugin Overview](./plugin-overview.md) ·
  [Inline Completion Request Flow](./inline-completion-request-flow.md)
