# Developing an Inbound Chat Adapter

This guide explains how to add support for a chat platform that delivers messages by webhook (LINE, Microsoft Teams, ...), building on the inbound webhook foundation added in feature 044. It complements `docs/slack_gateway_setup.md` / `docs/discord_gateway_setup.md`, which document *operator* setup for the existing outgoing-connection adapters; this document is for *developers* implementing a new adapter class.

See also:

- `specs/044-inbound-chat-webhook/contracts/inbound_adapter.md` — the full method-level contract for `InboundAdapter`
- `specs/044-inbound-chat-webhook/contracts/webhook_endpoint.md` — the HTTP endpoint contract
- `docs/adr/017-inbound-chat-webhook-gateway.md` — why the endpoint lives in the Redmine web process while the gateway process still does all the polling and LLM work

## When to use InboundAdapter vs BaseAdapter

Use `RedmineAiHelper::ChatChannel::InboundAdapter` (not `BaseAdapter` directly) when the chat platform pushes events to a URL you register with it, rather than letting you open an outgoing connection. `InboundAdapter` already implements `#start` as a polling loop over the persistent queue table (`ai_helper_inbound_events`) that the webhook controller fills in; you only implement the platform-specific parsing and verification.

## Steps

### 1. Create the adapter file

Add `lib/redmine_ai_helper/chat_channel/adapters/<name>_adapter.rb`, following the same location convention as `slack_adapter.rb`/`discord_adapter.rb`. It is picked up automatically by the `Dir[...adapters/*_adapter.rb]` glob in `init.rb` — no manual registration.

```ruby
# frozen_string_literal: true

require "redmine_ai_helper/chat_channel/inbound_adapter"

module RedmineAiHelper
  module ChatChannel
    module Adapters
      class LineAdapter < InboundAdapter
        class << self
          def channel_type
            "line"
          end

          def required_setting_fields
            [ :bot_token ] # stored in AiHelperChatAdapterSetting#bot_token; use app_token too if needed
          end
        end

        def verify_request(request)
          # Compute the signature over request.raw_post (never the parsed
          # body) and compare it against the platform's signature header.
        end

        def parse_events(request)
          # Return an Array<Hash>; see "The event Hash" below. Return []
          # when the payload carries nothing to answer (e.g. a delivery
          # receipt or the bot's own message).
        end

        def send_message(channel_id:, thread_key:, text:)
          # Post the reply via the platform's REST API.
        end
      end
    end
  end
end
```

### 2. Implement `#verify_request(request)`

Required — there is no default implementation. Authenticity for a webhook-delivered message can only be established by the adapter itself (typically an HMAC signature over the raw body), since there is no Redmine session involved. Always compute the signature over `request.raw_post` — the exact bytes the platform signed — never over a re-serialized version of the parsed JSON, which is not guaranteed to be byte-identical.

### 3. Implement `#parse_events(request)`

Required. Convert the verified request into zero or more normalized event hashes:

| Key | Type | Required | Notes |
|-----|------|----------|-------|
| `:event_key` | String | yes | External event id; deduplication key |
| `:text` | String | yes | Question body, with mention markup already stripped |
| `:channel_id` | String | yes | Channel (or DM) identifier |
| `:thread_key` | String | yes | Thread identifier |
| `:message_ts` | String | no | Individual message id, if the platform has one |
| `:dm` | Boolean | no | Direct message flag (default `false`) |
| `:in_thread` | Boolean | no | Reply-in-thread flag (default `false`) |
| `:reply_metadata` | Hash | no | Platform-specific data needed later to reply; `AiHelperInboundEvent#reply_metadata=` JSON-encodes it on the way into the column |

Return exactly these keys — an event carrying anything else is logged as an error and skipped, since it cannot be stored.

Never include the bot's own messages, and never put speaker identity into `:reply_metadata` or `:text` (FR-003 — this plugin does not record who asked a question, only the configured service account that answers it, exactly as for the existing outbound adapters). A request that cannot be parsed (malformed JSON, an unexpected shape) should raise; the controller catches it, logs the full backtrace, and still returns `200` so the platform does not retry forever. The same holds for a single event that cannot be stored: it is logged with its backtrace and skipped, the other events of that delivery are still stored, and the platform still gets a `200`.

### 4. Implement `#challenge_response(request)` only if the platform needs it

Optional — the default returns `nil`. Some platforms verify a webhook URL at registration time with a handshake request (e.g. echoing back a `challenge` value). Return `{ status:, content_type:, body: }` for that request and `nil` for every normal event delivery. A non-nil return skips event storage entirely for that request.

### 5. Reply metadata, if the platform needs more than channel_id/thread_key to reply

`InboundAdapter#reply_metadata_for(thread_key:)` returns the parsed `reply_metadata` of the next claimed event of that thread, in claim order, and consumes it — so calling it once per `#send_message` walks the thread's events in the same order the worker answers them. Call it from `#send_message` if your platform's reply call needs something beyond `channel_id`/`thread_key` (e.g. a reply token). Most platforms that support pushing a message by channel id alone do not need this.

Call it exactly once per reply. A poll cycle claims a whole batch before the single worker answers any of it, so "the most recent event of this thread" is *not* the one being answered; the position is per thread and only advances when you call this method.

### 6. Settings and the webhook URL

No new settings model is needed: `AiHelperChatAdapterSetting` already has the columns every adapter shares (`enabled`, `app_token`, `bot_token`, execution account, default project). Declare whichever of `app_token`/`bot_token` your adapter needs via `required_setting_fields`, the same as an outbound adapter.

Once your adapter is enabled in *Administration → AI Helper → Chat integrations*, its block automatically shows the webhook URL to register with the external service:

```text
https://<Setting.host_name>/ai_helper/chat_webhook/<channel_type>
```

This is generic (`InboundAdapter.inbound?` returns `true` by default; `BaseAdapter.inbound?` returns `false`), so nothing adapter-specific needs to be added to the settings view.

## Constants you can rely on

Defined on `InboundAdapter` and shared by every inbound adapter:

| Constant | Default | Meaning |
|----------|---------|---------|
| `POLL_INTERVAL_SECONDS` | 2 | How often the gateway checks for new pending events |
| `FRESHNESS_LIMIT_SECONDS` | 120 | Events claimed after this many seconds since receipt are discarded, not answered |
| `RETENTION_DAYS` | 7 | How long a row survives (for deduplication) before deletion |
| `CLEANUP_INTERVAL_SECONDS` | 3600 | Minimum interval between retention cleanups |
| `POLL_BATCH_SIZE` | 20 | Rows fetched per poll |

## Reverse-proxy recommendations (rate limiting)

The plugin does not rate-limit the webhook endpoint itself (see ADR-017): that is left to the reverse proxy already in front of Redmine, matching how the rest of Redmine's public surface is protected. A minimal nginx example:

```nginx
limit_req_zone $binary_remote_addr zone=ai_helper_webhook:10m rate=20r/s;

location /ai_helper/chat_webhook/ {
    limit_req zone=ai_helper_webhook burst=40 nodelay;
    proxy_pass http://redmine_upstream;
}
```

Tune the rate to the traffic your integration actually expects; the endpoint's own work per request is cheap (verify, normalize, insert one row), so the limit mainly exists to bound abuse, not to protect the endpoint's own performance.

## Testing

Follow the reference inbound adapter pattern used by the plugin's own test suite (`test/unit/chat_channel/inbound_adapter_test.rb`): define a test-only subclass with instance- or class-level toggles for `verify_request`/`parse_events`/`challenge_response`, register it only inside the test file (never under `lib/`), and drive `#start` for one poll cycle by stubbing `InboundAdapter.timed_queue_pop` to call `#stop` as a side effect. This proves your adapter integrates with the shared `Gateway`/`MessageHandler` path without needing a real webhook call or a live chat platform.
