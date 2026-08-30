# ADR-032: Restore subscriptions/listen Rejection Under mcp 1.4.0

**Date**: 2026-08-28
**Status**: Accepted

## Context

ADR-031 made the `/ai_helper/mcp` endpoint reject `subscriptions/listen` (SEP-2575) via two
coordinated overrides on `RedmineAiHelper::Mcp::Transport < MCP::Server::Transports::StreamableHTTPTransport`:
a public `serves_subscriptions_listen?` hardcoded to `false` (capability-declaration honesty,
defence in depth), and a private `handle_subscriptions_listen` override returning a one-shot
404/`-32601` response. Under `mcp` 1.3.0, `handle_modern` called `handle_subscriptions_listen`
unconditionally on method-name match, without consulting `serves_subscriptions_listen?` at all.

`mcp` 1.4.0 changed this: `serves_subscriptions_listen?` now doubles as the gate condition for
whether `handle_modern` calls `handle_subscriptions_listen` in the first place
(`body[:method] == Methods::SUBSCRIPTIONS_LISTEN && serves_subscriptions_listen?`). Because this
plugin's override always returns `false`, upgrading to `mcp` 1.4.0 silently closes that gate: the
plugin's 404 rejection logic is never reached, and a `subscriptions/listen` request without an
`id` falls through to the gem's normal JSON-RPC notification handling, which returns an
unanswered HTTP 202 — reproducing the request-storm-enabling behavior ADR-031 fixed, for the
no-`id` case specifically (`research.md` §1–2 of
`specs/052-fix-mcp14-subscriptions-listen/`).

A prototype confirmed `discover_capabilities` is unaffected by this either way:
`RedmineAiHelper::Mcp::Server.build` already passes an explicit
`capabilities: { tools: {}, prompts: {}, resources: {}, logging: {} }` to `MCP::Server.new`, which
replaces rather than merges with the gem's defaults, so no `listChanged`/`subscribe` flags are
ever present to strip (`research.md` §3). `serves_subscriptions_listen?` returning `true` or
`false` makes no difference to the capability declaration under 1.4.0 — it now only controls the
rejection gate.

## Decision

Delete the `serves_subscriptions_listen?` override from `RedmineAiHelper::Mcp::Transport`,
letting it fall back to the gem's default (`true`, via the unset `serve_subscriptions_listen:`
constructor keyword). This keeps the 1.4.0 gate open, so the unchanged private
`handle_subscriptions_listen` override is reached again by method-name match alone, restoring the
one-shot 404/`-32601` rejection for both `id`-bearing and `id`-less requests.

The `handle_subscriptions_listen` override itself, and its docstring's grounding in the
observable 404/`-32601`/no-`listChanged` contract, are unchanged — feature 051's functional test
suite for `subscriptions/listen` passes against 1.4.0 with no test code changes, which is this
fix's own regression evidence (`research.md` §5).

## Consequences

- **Positive**: the request-storm mitigation from ADR-031 is intact again under `mcp` 1.4.0 —
  `id`-less `subscriptions/listen` requests get an immediate, observable 404 error instead of a
  silent 202.
- **Positive**: this removes one of the two gem-internal members ADR-031 recorded as a coupling
  risk (`serves_subscriptions_listen?`), leaving only `handle_subscriptions_listen`. This
  partially resolves the Negative consequence ADR-031 flagged about depending on two named
  internals.
- **Negative**: the plugin still overrides one private gem member
  (`handle_subscriptions_listen`), so it remains exposed to a future gem restructuring of that
  method; as before, this is only caught by running the functional test suite after a gem
  upgrade, not by a static contract.
- **Negative**: `serves_subscriptions_listen?` now silently means two different things across gem
  versions the plugin has targeted (1.3.0: capability-declaration honesty only, no gating effect;
  1.4.0: capability declaration plus the sole gate for `handle_subscriptions_listen`). Not
  overriding it ties this plugin's rejection behavior to the gem's default for that keyword
  remaining `true`; a future gem version flipping that default would reopen this exact regression
  and would only be caught by the same functional test suite.

## Alternatives Considered

- **Override `serves_subscriptions_listen?` to explicitly return `true`**: behaviorally identical
  to relying on the default, but leaves a no-op override in the code that merely echoes the gem's
  own default — against YAGNI/KISS. Deleting the override is simpler and communicates the actual
  intent more accurately: this plugin does not care about the value of
  `serves_subscriptions_listen?` itself, only that `handle_subscriptions_listen` is reached.
- **Pass `serve_subscriptions_listen: true` explicitly at the `Transport.new` call site**
  (`app/controllers/ai_helper_mcp_controller.rb`): adds a file and a line to state the same value
  the default already provides, with no gain in clarity over deleting the override.
- **Adopt the gem's new `serve_subscriptions_listen: false` constructor option as the rejection
  mechanism**, replacing the private `handle_subscriptions_listen` override: rejected. That option
  only prevents the gate from calling `handle_subscriptions_listen`; it does not change how
  `id`-less requests are dispatched, so they would still fall through to the notification path and
  return an unanswered 202 — failing this feature's core requirement (FR-002, spec Assumptions).
- **Leave `handle_subscriptions_listen` unoverridden and rely on the gem's standard 404
  delegation**: rejected — does not solve the `id`-less request problem either, for the same
  reason ADR-031 originally rejected it.

## References

- Supersedes the "override `serves_subscriptions_listen?`" element of ADR-031's Decision §2; does
  not modify ADR-031 itself (append-only).
- `specs/052-fix-mcp14-subscriptions-listen/research.md`, `contracts/transport-internal.md`
