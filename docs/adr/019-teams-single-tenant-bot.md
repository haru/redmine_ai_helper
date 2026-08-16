# ADR-019: Teams integration targets single-tenant bots (amends ADR-018)

**Date**: 2026-08-16
**Status**: Accepted

## Context

ADR-018 designed the Microsoft Teams inbound adapter around a bot registered as a *multi-tenant* Azure Bot resource, and described that configuration as the only one that works for the app-package installation flow Teams administrators use.

That premise no longer holds. Microsoft stopped registering multi-tenant bots on July 31, 2025: the Azure portal's **Type of App** list now offers only **Single Tenant** and **User-Assigned Managed Identity**, so a new integration cannot be created the way ADR-018 assumed. Existing multi-tenant bots keep working, but none can be created, and reaching organizations outside your own is now expected to go through the Teams Store / AppSource rather than through a multi-tenant registration.

The two directions of Bot Framework authentication are affected differently:

- **Connector → bot** (the deliveries this integration verifies) is unchanged. The token still carries `iss = https://api.botframework.com`, is still signed with the keys published at `https://login.botframework.com/v1/.well-known/openidconfiguration`, and still names the bot's app id as its audience, whatever the app type.
- **Bot → Connector** (posting the answer) differs. A multi-tenant bot requests its token from the fixed `botframework.com` tenant; a single-tenant bot's credentials exist only in its own directory, so the request must go to that directory instead. The scope, `https://api.botframework.com/.default`, is the same either way.

## Decision

1. **The integration targets single-tenant bots only.** No support is kept or added for multi-tenant registrations. The setup guide instructs operators to choose **Single Tenant**.

2. **Both access tokens are requested from the configured tenant.** `TeamsAdapter` builds one token endpoint, `https://login.microsoftonline.com/<tenant_id>/oauth2/v2.0/token`, for the Bot Connector and for Microsoft Graph alike; only the requested scope separates them. The `tenant_id` setting introduced by ADR-018 therefore carries a second responsibility, and a wrong value now also makes every reply fail.

3. **Request verification is unchanged.** The issuer, the JWKS source, the audience, the lifetime checks and the `serviceUrl` comparison stay exactly as ADR-018 decision 1 specified.

4. **The tenant comparison stays, with a new justification.** ADR-018 justified it by multi-tenant bots being installable elsewhere. With a single-tenant bot no other organization can install the app at all, but the check is kept as defence in depth: the Bot Framework signature attests that Microsoft sent the request, never which organization it originated in, and the configured tenant is the only thing in the system that does.

## Consequences

**Positive**:

- The integration can be set up again with what Azure offers today.
- One token endpoint instead of two special cases: the audience table collapses to a scope-per-audience map, and the tenant is read from the settings row in both cases.
- The `tenant_id` setting is now load-bearing in both directions, so a misconfigured tenant fails loudly at the first reply instead of silently accepting a wider set of senders.

**Negative**:

- Operators with an existing multi-tenant bot cannot use this integration with it; they must register a single-tenant bot. This is accepted rather than worked around, because supporting both would mean carrying an app-type setting for a configuration Microsoft no longer issues.
- Serving organizations other than your own now requires publishing the Teams app through AppSource, which is outside this plugin's scope.
- ADR-018's Context section still describes the multi-tenant premise; it is preserved as written, and this record is what supersedes that paragraph.

## Alternatives Considered

- **Adding an app-type setting (single vs multi tenant)** (rejected): a new settings column and a branch in the token endpoint, kept alive for registrations that can no longer be created. The Teams adapter had not shipped when this came up, so there is no installed base to keep compatible.
- **Requesting the Connector token from `botframework.com` regardless of app type** (rejected): a single-tenant app has no service principal in that directory, so the request is rejected — this is exactly the failure the change exists to fix.
- **Trying the tenant endpoint and falling back to `botframework.com`** (rejected): a fallback that hides a configuration error behind a second request, which the constitution forbids; a rejected credential must surface immediately.
