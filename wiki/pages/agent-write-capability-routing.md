---
title: Agent Write-Capability Routing
type: decision
sources: [S016, S017]
updated: 2026-11-21
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
- **Runtime guard, not pre-validation**: `generate_steps`'s structured output
  gains a required `requires_write` boolean per step (one extra field, same
  LLM call). Immediately before dispatch, `LeaderAgent#execute_chat_room_steps`
  checks `step["requires_write"] && !agent.can_write?`; a match skips the LLM
  call and records the step as a structured failure in
  `ChatRoom#step_results`. No automatic re-routing — that would hide the
  routing failure and risks silently picking a different write agent (S016).
  This same path also covers read-only mode, since `can_write?` becomes
  `false` for every tool-classified agent once read-only mode filters out
  `write: true` tools.
- **Execution behaviour**

Skipped steps stay visible to later steps, the final answer is grounded in execution results, and unclassifiable tools default to write-capable. See [Agent Write-Capability: Execution Behaviour](./agent-write-capability-execution.md) (S016).

## Rejected alternatives

- Adding `can_write` to `list_agents` and a routing rule to the planning
  prompt: rejected — it would label dual-role agents as write-only and block
  read-only steps from ever reaching them (S016).
- A dedicated plan-validation phase before execution: rejected — it
  duplicates the per-step guard and still needs its own read-only-mode
  handling (S016).
- Guarding `can_write?` with `respond_to?(:write_tool?)`: rejected as the
  same class of silent-failure fallback this decision exists to remove
  (S016).
- Automatically re-routing a misassigned step to a capable agent: rejected —
  hides the routing failure from the user (S016).

## Related

- [Tool System](./tool-system.md) — the `write_tool?` / `write:` metadata
  this reuses.
- [Multi-Agent Architecture](./multi-agent-architecture.md) — where
  `LeaderAgent` planning and step dispatch live.
- [MCP Integration](./mcp-integration.md) — why generated MCP agents can't
  use the default `can_write?`.
