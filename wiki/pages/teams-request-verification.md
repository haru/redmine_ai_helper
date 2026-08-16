---
title: Teams Request Verification
type: reference
sources: [S021, S022, S023]
updated: 2026-08-16
---

# Teams Request Verification

What `TeamsAdapter#verify_request` checks before a Teams activity is allowed to
become an inbound event. Two independent gates live here: Bot Connector JWT
validation and allowed-tenant matching (S021).

## Bot Connector JWT

The token arrives as `Authorization: Bearer <JWT>` and is validated per the Bot
Connector specification (S021):

| Item | Value |
|---|---|
| OpenID metadata | `https://login.botframework.com/v1/.well-known/openidconfiguration` |
| Signing keys | the metadata's `jwks_uri` (currently `…/v1/.well-known/keys`) |
| Algorithm | `RS256` |
| `iss` | `https://api.botframework.com` |
| `aud` | the configured application (App) ID |
| Lifetime | `exp` / `nbf`, 300s clock skew |
| `serviceUrl` claim | must equal the body's `activity.serviceUrl` |

JWKS is cached in-process and refreshed every 24 hours per Microsoft's guidance;
an unknown `kid` triggers **one** immediate refetch, so a key rotation does not
drop every request until the cache expires (S021).

The keys are cached on the adapter **class**, not the instance: `verify_request`
runs in the Redmine **web** process, which builds a fresh adapter per delivery,
so an instance cache would be re-read every request and the 24-hour lifetime
would never take effect. Nothing leaks — JWKS is Microsoft's public document.
The adapter's other two caches are instance-level (S022); see
[Teams Inbound Chat Adapter](./teams-adapter.md).

Verification uses the `jwt` gem, added to the plugin `Gemfile` as
`gem "jwt", "~> 3.2"` — 3.2.0 was already present, but only indirectly through
Redmine's `oauth2`, which is not a dependency the plugin may rely on. Hand-rolled
OpenSSL verification was rejected: confusing `aud`/`iss`/`exp`/`nbf`/`alg` is
directly a security defect, so a proven library is the simpler and safer choice
under Constitution V. The `serviceUrl` match is a Microsoft-mandated check that
stops a stolen token from redirecting answers to another service URL (S021).

`verify_request` has no base implementation precisely because only the adapter
can establish authenticity — see
[Developing an Inbound Chat Adapter](./inbound-adapter-development.md). Bot
Framework offers no alternative proof, so shared-secret schemes were rejected,
as was trusting `tenant.id` alone, which anyone can forge (S021).

## Allowed-tenant gate

`activity.channelData.tenant.id` (falling back to
`activity.conversation.tenantId`) is compared against the configured tenant id;
a mismatch makes `verify_request` return `false`, which the endpoint answers
**401** with nothing stored (S021).

The gate belongs next to signature verification rather than downstream, because
a Bot Framework signature attests that **Microsoft** sent the request, never
which organization it came from — `iss` is `https://api.botframework.com` and
`aud` is the bot's own App ID, so JWT validation alone says nothing about the
sender's tenant. The configured tenant id is the only thing in the system that
does (S023). With the bot registered as single-tenant (**ADR-019**) no outside
organization can install the app, so the gate is defence in depth rather than
the load-bearing check it was under the original multi-tenant premise
(S022). Placing the check in `verify_request` also settles
the rejection before the event is queued, which is what guarantees no answer is
ever generated for a foreign tenant (S021).

Rejected alternatives: returning `[]` from `parse_events` with a 200, which
would be indistinguishable from an unparseable or non-question delivery and
would acknowledge receipt to an outside organization; and checking the tenant in
the gateway at reply time, which leaves a larger attack surface (S021).

A tenant mismatch is logged with `ai_helper_logger.warn` **including** the
tenant id — a directory identifier, not sensitive — alongside the controller's
existing `request verification failed for channel_type=teams` line. Credentials
are never logged (S021).

Both gates are decision 1 of **ADR-018** (Accepted 2026-08-14): an unauthorized
organization never reaches the queue, let alone an answer — the check holds
before any LLM work, any queue row, and any log of question content (S022).

## Related

- [Teams Inbound Chat Adapter](./teams-adapter.md) — the class these gates live in.
- [Teams Activity Mapping](./teams-activity-mapping.md) — the filtering that
  runs after verification succeeds.
- [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md) — the controller
  that turns `false` into a 401.
