---
title: Nginx SSE Proxy Settings
type: howto
sources: [S002]
updated: 2026-08-01
---

# Nginx SSE Proxy Settings

The plugin streams chat responses via **SSE (Server-Sent Events)**. Behind an
Nginx reverse proxy, response buffering must be disabled or streaming breaks
(S002).

## The failure it prevents

Without these settings the plugin may **fail to authenticate users**, behaving
as if requests come from an anonymous user (S002). This is the tell-tale symptom
of a mis-proxied SSE stream — worth remembering when "logged-in users appear
anonymous" is reported.

## The five directives

Add these to the existing Redmine `location` block, then `nginx -s reload`
(S002):

```nginx
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_buffering off;
proxy_cache off;
proxy_set_header X-Accel-Buffering no;
```

`proxy_http_version 1.1` and `proxy_set_header Connection ""` are **required**:
they enable HTTP/1.1 persistent connections to the upstream. Without them Nginx
defaults to HTTP/1.0, which does not properly support SSE streaming (S002).

## Related

- [Plugin Overview](./plugin-overview.md)
