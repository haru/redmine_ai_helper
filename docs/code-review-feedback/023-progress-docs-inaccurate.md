# CRF-023: Progress docs described the plan line, the no-step case and permissions inaccurately

**Date**: 2026-10-13
**Source**: Local AI review (`/speckit-review-run`, comments agent)
**Feature**: branch `073-chat-channel-progress`
**Files**: docs/adr/054-chat-channel-progress-message.md, docs/slack_gateway_setup.md, docs/discord_gateway_setup.md, wiki/pages/chat-progress-message.md, lib/redmine_ai_helper/chat_channel/adapters/slack_adapter.rb, lib/redmine_ai_helper/chat_channel/adapters/discord_adapter.rb
**Category**: doc-comment
**Related**: CRF-007, CRF-011, CRF-005

## Feedback

- Docs said a question needing no steps shows no progress message, but planning posts "creating plan" first and the message is then deleted.
- The first line was called "the plan"; it is the status text "Creating execution plan...", and the "generating final response" line was not mentioned.
- The Discord permission list omitted Read Message History, which a `message_reference` needs; the `chat:write` scope description omitted update and delete.
- `MAX_MESSAGE_LENGTH` comments and the Slack class header did not mention progress messages or `chat.update`/`chat.delete`.
- ADR cost note omitted the final delete call.

## Original Code

"Questions that need no steps show no progress message." / "(the plan, then each step)"

## Fix

Rewrote these passages to the real sequence and scope in the ADR, wiki, both setup guides and the adapter comments.

## Root Cause

The AI described the intended happy path from the spec's summary instead of tracing `LeaderAgent` order (planning line before `generate_steps`) and each adapter's requests. It named lines by role rather than by the actual i18n text.

## Prevention

- When a doc states when something is or is not shown, trace the code path that emits it, including the earliest emission, and list every line/permission/scope it uses.
- After adding a second use of a constant or scope, update its comment and the doc that lists it.

**Promoted to**: Not yet
