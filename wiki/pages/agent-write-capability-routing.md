---
title: Agent Write-Capability Routing
type: decision
sources: [S016, S017]
updated: 2026-08-16
---

# Agent Write-Capability Routing

Bug: `LeaderAgent` picked the agent for a step from backstory wording alone,
so "create an issue" requests were assigned to `issue_read_agent` (renamed
from `issue_agent`, which holds no write tools — see below). The step
silently never ran, yet the final answer still reported the issue as created
(S016).

> ⚠ update (S017): the backstory rewording described below as the fix for
> correct routing did not hold up in production. Real "create a ticket"
> requests logged on the running instance were routed to the read-only agent
> 100% of the time, both before and after the rewording — the runtime guard
> below correctly stopped the false "created" report, but ticket creation
> itself kept failing. `issue_agent`/`issue_update_agent` were renamed to
> `issue_read_agent`/`issue_write_agent` so the read/write distinction is
> carried by the `agent_name` token the router reads for every candidate,
> not only by prose inside `backstory` (S017).

## Decision

- **`BaseAgent#can_write?`** = `available_tool_classes.any?(&:write_tool?)` —
  reuses the existing `write_tool?` metadata from the
  [Tool System](./tool-system.md) DSL rather than adding a new declaration
  mechanism (S016).
- **Never exposed to the router**: `AgentList#list_agents` still returns only
  `agent_name`/`backstory`. Dual-role agents such as `wiki_agent` (holds both
  `WikiTools` and `WikiWriteTools`) would otherwise read as "write
  specialists" and get excluded from read-only assignments. Routing
  correctness was first pursued by rewording the `issue_agent` /
  `issue_update_agent` backstories (S016); production evidence showed this
  did not work (see the update note above), so the agents were also renamed
  to `issue_read_agent` / `issue_write_agent` to carry the distinction in the
  `agent_name` field itself (S017).
- **Enforced at dispatch, not in the plan**: a misassignment is caught by a
  per-step runtime guard rather than by pre-validating the plan or re-routing
  it. That half of the decision — the `requires_write` flag, skipped-step
  recording, and how the final answer reports what actually ran — lives on
  [Write-Capable Step Guard](./agent-write-step-guard.md) (S016).

## Rejected alternatives

- Adding `can_write` to `list_agents` and a routing rule to the planning
  prompt: rejected — it would label dual-role agents as write-only and block
  read-only steps from ever reaching them (S016).

The alternatives rejected for the guard itself — plan-validation phases,
`respond_to?` guards, automatic re-routing — are listed on
[Write-Capable Step Guard](./agent-write-step-guard.md) (S016).

## Related

- [Write-Capable Step Guard](./agent-write-step-guard.md) — the other half:
  what happens at dispatch when a step needs write and the agent lacks it.
- [Tool System](./tool-system.md) — the `write_tool?` / `write:` metadata
  this reuses.
- [Multi-Agent Architecture](./multi-agent-architecture.md) — where
  `LeaderAgent` planning and step dispatch live.
- [MCP Integration](./mcp-integration.md) — the agents whose capability
  cannot be classified.
