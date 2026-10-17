# SF-003: Limited prompt reordering to the common agent prompt and missed the leader prompt

**Date**: 2026-10-11
**Feature**: specs/070-prompt-caching (branch `feature/070-prompt-caching`)
**Artifact**: spec.md
**Category**: scope-gap
**Related**: SF-002

## Feedback

During `/speckit-clarify`, the user asked: "The system prompt contains the current time, so caching does not work after it. If we used the same time for the whole duration of one user inquiry, would the cached range get larger?" Investigating the question showed that the leader agent's system prompt was not covered by the reordering requirement. The user agreed to add it (and agreed not to fix the time per inquiry, because cache entries are not shared across agents and the gain would be limited to re-invocations of the same agent).

## What the AI Wrote

FR-007: "Values that change per call (the current time) MUST be placed after the fixed parts (plugin description, role, language instruction, agent backstory, read-only notice) ..."

The listed parts are those of `assets/prompt_templates/base_agent/system_prompt.yml` only. The background section also described only that template.

## Correction

FR-007 now covers two system prompts: FR-007a (the common agent prompt, variable value: current time) and FR-007b (the leader agent prompt, variable values: current time, site and current project information, current page information, user information). FR-007c states that the time is not unified across one inquiry. An assumption was added that cache entries are not shared across agents.

## Root Cause

The AI read `BaseAgent#system_prompt` in `lib/redmine_ai_helper/base_agent.rb`, saw the time in the middle of the template, and generalized that to "the system prompt". It did not check whether any agent overrides `system_prompt`. `LeaderAgent#system_prompt` (`lib/redmine_ai_helper/agents/leader_agent.rb`) overrides it with `RedmineAiHelper::Util::SystemPrompt`, which uses a different template (`assets/prompt_templates/leader_agent/system_prompt.yml`) containing the time plus user-, page-, and project-specific values. The idea memo named only `BaseAgent#system_prompt`, and the AI took that as the full list of affected places.

## Prevention

When a requirement targets the output of a base-class method (prompts, payloads, settings), search for every override of that method (`grep -rn "def <method>"`) and every template that produces the same kind of output, and list each one explicitly in the requirement. Do not treat the locations named in an idea memo or request as exhaustive.

**Promoted to**: AGENTS.md
