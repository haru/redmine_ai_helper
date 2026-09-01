# ADR-016: Rename IssueAgent/IssueUpdateAgent to IssueReadAgent/IssueWriteAgent

**Date**: 2026-08-07
**Status**: Accepted

## Context

[ADR-015](015-agent-write-capability-routing.md) added a runtime guard that stops a misrouted write step from being silently reported as completed, but explicitly accepted as a known negative consequence that "correct assignment now rests entirely on backstory wording, which is exactly the mechanism that failed originally" — the guard catches the failure, it does not prevent the misrouting.

Production logs from the running instance (`log/ai_helper.log`) confirmed this predicted risk materialized in practice. Filtering to genuine user-issued "create a ticket" requests (excluding test-suite noise, which logs to the same file regardless of `RAILS_ENV`), every single request — both before and after the ADR-015 backstory rewrite — was routed to `issue_agent` instead of `issue_update_agent`:

| Time | Request | Routed to |
|------|---------|-----------|
| 17:17 | "ジムに行くというチケットを作って" | `issue_agent` |
| 17:21 | "エアコンを掃除するというチケットを作って" | `issue_agent` |
| 22:32 | "犬の散歩に行く、というチケットを作って" | `issue_agent` |
| 22:37 | "犬の散歩に行く、というチケットを作って" (retry) | `issue_agent` |
| 22:37 | "犬の散歩に行く、というチケットを作って" (retry) | `issue_agent` |
| 22:38 | "キャットフードを買うというチケットを作って" | `issue_agent` |

Before ADR-015's runtime guard, this misrouting was invisible: `issue_agent` would produce a draft and the leader would report it as a completed creation (the original bug). After the guard, the same misrouting is honestly reported as a failure — an improvement, but ticket creation still fails 100% of the time in practice, which defeats the feature's actual goal (spec `043-issue-create-routing`, User Story 1).

The ADR-015 backstory rewrite made the negation more explicit ("you never create, update, or delete issues yourself — only issue_update_agent does that") but, in doing so, also increased the raw frequency of the word "作成"/"create" inside `issue_agent`'s own backstory (four occurrences, up from three), which is the exact failure mode ADR-015's Context section describes: an affirmative-sounding clause outweighing the negation that follows it.

## Decision

Rename the two agent classes so the read/write distinction is carried by the `agent_name` token itself, not only by prose inside `backstory`:

- `RedmineAiHelper::Agents::IssueAgent` → `RedmineAiHelper::Agents::IssueReadAgent` (file, class, prompt-template directory, i18n namespace, all renamed from `issue_agent` to `issue_read_agent`)
- `RedmineAiHelper::Agents::IssueUpdateAgent` → `RedmineAiHelper::Agents::IssueWriteAgent` (same treatment, `issue_update_agent` → `issue_write_agent`)

`agent_name` is a short, structurally prominent field in the `generate_steps` routing prompt (`AgentList#list_agents` emits `{agent_name, backstory}` for every candidate). It is far less likely to be diluted by surrounding prose than a clause buried in a paragraph, and pairing `_read_` / `_write_` makes the axis that actually matters for FR-001/FR-002 explicit at the identifier level rather than requiring the LLM to infer it from backstory wording alone.

No change was made to `BaseAgent#can_write?`, the `requires_write` step field, or the runtime guard from ADR-015 — this ADR only addresses the assignment step, not the safety net.

## Consequences

**Positive**:
- The read/write axis is now visible at the same structural level the router already reads for every other assignment decision (`agent_name`), instead of relying solely on the router correctly weighing an affirmative clause against a later negation.
- No new mechanism was introduced; this is a rename plus a matching backstory-text update (both backstories now refer to each other by their new names), so ADR-015's guard and `record_skipped_step` behavior are unaffected.

**Negative**:
- This is a large mechanical change: two class/file renames plus every reference in tests, prompt templates, locale files, and documentation. External integrations that reference the old agent names directly (if any exist outside this repository, e.g. custom automation against internal APIs) would break.
- The rename does not *guarantee* correct routing — it removes one specific, evidenced source of ambiguity (word-frequency dilution in prose) but the assignment decision is still made by an LLM reading free-text backstories, and ADR-015's accepted risk ("correct assignment rests entirely on backstory wording") still applies in principle. Real-world routing accuracy after this change should be re-measured against production logs the same way the regression here was detected.

## Alternatives Considered

- **Keep the names, rewrite the backstory again**: rejected as the immediate next step, because the previous rewrite (ADR-015) already tried to strengthen the negation in prose and measurably failed in production (100% misrouted). Repeating the same category of fix without changing the mechanism was judged unlikely to converge.
- **Add a deterministic pre-routing check (e.g., keyword rules) ahead of the LLM call**: rejected — FR-002b (established in spec `043-issue-create-routing`) prohibits adding LLM round-trips for this determination, and a keyword-rule layer outside the LLM call would duplicate routing logic the leader agent is supposed to own, reintroducing the kind of parallel decision path ADR-015 already rejected for plan validation.
- **Leave `issue_update_agent` named as-is and rename only `issue_agent`**: rejected — an asymmetric rename (`issue_read_agent` vs `issue_update_agent`) would not give the router a matching contrastive pair, weakening the same signal this ADR relies on.
