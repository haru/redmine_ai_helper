# ADR-015: Guard write-capable steps with an internal capability check that is never exposed to the router

**Date**: 2026-08-07
**Status**: Proposed

## Context

`LeaderAgent#generate_steps` assigns each step of a plan to a specialized agent by asking the LLM to read the agent's `backstory` text. `IssueAgent`'s backstory read "You can also create or suggest updates for issues ... However, you cannot create or update issues yourself." — the affirmative clause reads as a stronger match for a "create an issue" request than the negation that follows it. As a result, ticket-creation requests were frequently routed to `IssueAgent`, which has no write tools (`available_tool_classes.any?(&:write_tool?)` is `false`). The step then ran against `IssueAgent`'s tool-use loop, which naturally cannot create anything, and `LeaderAgent#perform_user_request` generated the final answer from a success-presupposing instruction string ("All agents have completed their tasks...") with no structured signal that the step never wrote anything — so the user was told a ticket was created when it was not.

Two failure points needed independent fixes: (1) the assignment decision itself had no structural signal to route on, only prose, and (2) even a correct assignment offers no protection against a *future* misassignment, and the final-answer generation had no way to know a step failed to execute.

## Decision

1. **Derive write capability structurally, for internal use only.** `BaseAgent#can_write?` is defined as `available_tool_classes.any?(&:write_tool?)`, reusing the `write_tool?` metadata from ADR-005 rather than introducing a new declaration mechanism. Because `available_tool_classes` already excludes write tools under read-only mode, `can_write?` is `false` for every agent when read-only mode is on, with no additional code. It is a plain Ruby predicate — no LLM call is involved.
2. **Never expose that capability to the router.** `AgentList#list_agents` is left unchanged: it returns only `agent_name` and `backstory`, and no `can_write`-based rule is added to `generate_steps.yml` / `_ja.yml`. Agents are **not** partitioned into read-only and write-only roles — `WikiAgent` holds `WikiTools` (read) *and* `WikiWriteTools` (write), so `can_write? == true` means "can perform writes", not "is the write agent". Presenting it as routing input made dual-capability agents read as write specialists and blocked read-only steps from being assigned to them. Correct assignment is instead pursued through the backstories of `IssueAgent` (read-only-first framing) and `IssueUpdateAgent` (sole actual creator/updater).
3. **Declare write intent per step, and guard it at execution time.** The `generate_steps` JSON schema gains a required `requires_write` boolean per step — one extra field in the existing single structured-output call, so the number of LLM requests is unchanged. Immediately before dispatching a step, `LeaderAgent#execute_chat_room_steps` checks `step["requires_write"] && !agent_instance.can_write?`. If true, the step is never sent to the agent (one *fewer* LLM call) — instead `ChatRoom#record_skipped_step` records it as a failure, and the loop continues to the next step. No fallback re-routing is attempted.
4. **Make step outcomes structured, not just chat history.** `ChatRoom#step_results` accumulates `{agent, step, status, error}` for every step, populated from the `TaskResponse` returned by `send_task` (or directly by `record_skipped_step` for guard failures). `ChatRoom#execution_results_json` serializes this in plan order. `LeaderAgent#perform_user_request` passes it into `generate_final_response` via a new `%{execution_results}` interpolation argument, and the instruction string (all 8 locales) was rewritten to remove the success presupposition, require treating `execution_results` as the only source of truth, forbid describing an `error` step as completed, and forbid leaking internal routing details (agent names) into the user-facing answer.
5. **No pre-execution validation phase.** The guard runs per step, immediately before that step would be sent, rather than validating the whole plan up front. This keeps the enforcement point identical for both causes of a write/no-write mismatch — an LLM misassignment and read-only mode being enabled after the plan was drafted — without adding a second code path.

## Consequences

**Positive**:
- A misrouted write step can no longer produce a false "created" report: it is either executed by a capable agent, or recorded as a structured failure that the final-answer prompt is required to reflect.
- Dual-capability agents keep working for both kinds of work. Because capability never reaches the prompt, a read-only step assigned to `WikiAgent` is dispatched exactly as before.
- The runtime guard also transparently covers read-only mode: since `can_write?` becomes `false` for all agents in that mode, a write step that slips through planning fails via the exact same path as a misassignment, with no dedicated read-only branch.
- No additional LLM round-trips. `requires_write` rides along in the existing `generate_steps` call, `can_write?` is local Ruby, and a guarded step skips the call it would otherwise have made.
- `AgentList#list_agents` keeps its original signature and payload, so the routing prompt does not grow.

**Negative**:
- Correct assignment now rests entirely on backstory wording, which is exactly the mechanism that failed originally. The guard prevents the *false completion report* but does not steer the step to the right agent, so a badly worded future backstory would resurface as visible step failures rather than as silent misreports. This was accepted as the cost of not breaking dual-capability agents.
- The guard cannot distinguish "assigned to the wrong agent" from "this agent legitimately cannot do this"; both surface identically to the user as an unexecuted step.
- A misassigned write step is not automatically retried against the correct agent. The user sees a failure for that step and may need to re-ask; automatic fallback re-routing was explicitly rejected (see below).

## Alternatives Considered

- **Expose `can_write` in the agent list and add a routing rule to the prompt**: implemented first, then reverted. It assumed agents split cleanly into read-only and write-only roles. They do not — `WikiAgent` holds both `WikiTools` and `WikiWriteTools` — so the rule "assign `requires_write: true` steps only to `can_write: true` agents", together with "split mixed read/write requests across different agents", made `wiki_agent` read as the write specialist and interfered with routing plain Wiki lookups to it.
- **Fix only the backstory wording, with no runtime check at all**: rejected — the original false-completion bug would remain reachable whenever the LLM misreads a backstory, since nothing would detect that the assigned agent never performed the write.
- **Add a dedicated plan-validation phase before execution**: rejected — it would duplicate the same `requires_write` vs. `can_write` comparison the runtime guard already performs, and would need its own handling for the read-only-mode case, without preventing anything the per-step guard doesn't already catch.
- **Automatically re-route a misassigned step to a capable agent**: rejected — it hides the routing failure from the user and risks looping or silently changing which agent performs a sensitive write, which conflicts with the plugin's no-implicit-fallback principle.
- **Guard inside `ChatRoom#send_task` instead of `LeaderAgent#execute_chat_room_steps`**: rejected — `ChatRoom` is a generic message-passing substrate with no knowledge of planning concepts like `requires_write`; the assignment/guard responsibility belongs with `LeaderAgent`, which owns the plan.
