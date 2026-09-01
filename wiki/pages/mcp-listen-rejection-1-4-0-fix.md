---
title: MCP subscriptions/listen 1.4.0 Fix
type: decision
sources: [S030, S031]
updated: 2026-08-28
---

# MCP `subscriptions/listen` 1.4.0 Fix (ADR-032)

Follow-up to [MCP subscriptions/listen Rejection](./mcp-listen-rejection.md)
(ADR-031). ADR-032 is append-only with respect to ADR-031 — it supersedes
only the `serves_subscriptions_listen?` half of ADR-031's fix, not the ADR
itself (S030, S031).

**The regression**: upgrading the `mcp` gem from 1.3.0 to 1.4.0 silently
broke ADR-031's part 2. `serves_subscriptions_listen?` changed from an inert
capability-honesty flag into **the gate condition itself** for whether
`handle_modern` calls `handle_subscriptions_listen`
(`body[:method] == SUBSCRIPTIONS_LISTEN && serves_subscriptions_listen?`).
Because the plugin's override hardcoded `false`, the gate stayed permanently
closed under 1.4.0: `handle_subscriptions_listen` was never reached, and a
`subscriptions/listen` request **without an `id`** fell through to the gem's
normal JSON-RPC notification handling, returning an unanswered HTTP 202 —
reproducing the request-storm-enabling behavior ADR-031 fixed, for the
no-`id` case specifically. Requests *with* an `id` happened to still work,
masking the regression (S030, S031).

`discover_capabilities` was confirmed unaffected either way: `Server.build`
already passes an explicit `capabilities:` hash that *replaces* rather than
merges with the gem's defaults, so no `listChanged`/`subscribe` flags are
ever present to strip regardless of `serves_subscriptions_listen?`'s value
(S030, S031).

**Fix**: delete the `serves_subscriptions_listen?` override entirely, letting
it fall back to the gem's default (`true`, via the unset
`serve_subscriptions_listen:` constructor keyword). This keeps the 1.4.0 gate
open, so the unchanged private `handle_subscriptions_listen` override is
reached again by method-name match alone — restoring the one-shot
404/`-32601` rejection for both `id`-bearing and `id`-less requests, with no
change to `handle_subscriptions_listen` itself or to feature 051's test suite
(S030, S031).

> **Gem-version coupling gotcha, updated**: only one gem-internal member is
> now overridden (`handle_subscriptions_listen`, private) — down from two,
> since `serves_subscriptions_listen?` is no longer touched. This partially
> resolves ADR-031's Negative consequence about depending on two named
> internals, but the 1.3.0→1.4.0 upgrade is itself the concrete case of the
> risk ADR-031 warned about: a gem restructuring changed what
> `serves_subscriptions_listen?` means with **no** Ruby-level error, caught
> only by the functional test suite. Relying on the gem's default now also
> means the plugin's rejection behavior is tied to that default remaining
> `true`; a future gem version flipping it would reopen this exact regression
> and, again, would only be caught by that same test suite (ADR-032
> Consequences; S030, S031).

## Alternatives rejected

- Override `serves_subscriptions_listen?` to explicitly return `true` instead
  of deleting it: behaviorally identical to the gem default, but leaves a
  no-op override that only echoes the gem's own default — against YAGNI/KISS
  (S030, S031).
- Pass `serve_subscriptions_listen: true` explicitly at the `Transport.new`
  call site instead: adds a file/line to state the same value the default
  already provides, no clarity gain (S030, S031).
- Adopt the gem's new `serve_subscriptions_listen: false` constructor option
  as the rejection mechanism, replacing the `handle_subscriptions_listen`
  override: rejected — that option only closes the gate; `id`-less requests
  would still fall through to the notification path and return an unanswered
  202, failing FR-002 (S030, S031).
- Leave `handle_subscriptions_listen` unoverridden and rely on the gem's
  standard 404 delegation: rejected — doesn't solve the `id`-less request
  problem either, for the same reason ADR-031 originally rejected it (S030,
  S031).

## Related

- [MCP subscriptions/listen Rejection](./mcp-listen-rejection.md) — ADR-031:
  the original request-storm fix this one patches.
- [MCP Server Endpoint](./mcp-server-endpoint.md) — the endpoint this
  decision applies to.
