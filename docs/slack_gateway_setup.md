# Slack Gateway Setup Guide

This guide explains how to connect the Redmine AI Helper to a Slack workspace so users can ask the AI Helper questions from Slack channels or direct messages and receive answers in the same thread.

The integration uses Slack **Socket Mode**: the gateway process opens an outgoing WebSocket connection to Slack, so **no public URL is required** for your Redmine server.

## Requirements

- Redmine 6.x with the `redmine_ai_helper` plugin installed, migrated, and a working model profile (the web chat must already work).
- Permission to create apps in your Slack workspace.
- Slack users who should use the integration must have the **same email address** on their Slack profile and their active Redmine account.

## 1. Create the Slack app

1. Open <https://api.slack.com/apps> and choose **Create New App** (from scratch).
2. Under **Socket Mode**, enable Socket Mode and generate an **App-Level Token** with the `connections:write` scope. Note the token (starts with `xapp-`).
3. Under **OAuth & Permissions → Bot Token Scopes**, add:
   - `app_mentions:read` — receive mentions in channels
   - `im:history` — receive direct messages
   - `chat:write` — post replies
   - `users:read` and `users:read.email` — resolve the speaker's email address
   - `reactions:write` — show the "processing" reaction
4. Under **Event Subscriptions → Subscribe to bot events**, add:
   - `app_mention`
   - `message.im`
5. Install the app into the workspace and note the **Bot User OAuth Token** (starts with `xoxb-`).

## 2. Configure Redmine

1. Go to **Administration → AI Helper → Chat integrations** tab.
2. In the **Slack** section, check **Enable**, paste the App Token (`xapp-`) and Bot Token (`xoxb-`), and save.
3. Optionally select a **Default project for direct messages**. DMs to the bot are answered in this project's context; without it, DMs receive a guidance message.
4. Under **Channel bindings**, map each Slack channel to a Redmine project:
   - Channel ID: open the channel in Slack, copy the ID from the URL or channel details (starts with `C`).
   - Channel name is optional display text for this screen.
   - One channel maps to exactly one project. The project must have the **AI Helper** module enabled.

## 3. Run the gateway

The gateway is a resident process, separate from the Redmine web server:

```bash
cd /path/to/redmine
bundle exec rake redmine:plugins:ai_helper:chat_channel:gateway RAILS_ENV=production
```

On success, `log/ai_helper.log` records the connection establishment (`hello` received). With invalid tokens the gateway logs the authentication error and exits with status **0** so the supervisor does not keep retrying — fix the tokens and start it again.

The gateway reconnects automatically on Slack-initiated refreshes, network errors (exponential backoff up to 60 s), missed ping responses, and clean closes that never received `hello` (suspected handshake rejection). Stop it with `SIGTERM` or `Ctrl+C`; queued messages are drained before exit.

### Running under systemd (example)

```ini
[Unit]
Description=Redmine AI Helper chat gateway
After=network.target

[Service]
Type=simple
User=redmine
WorkingDirectory=/path/to/redmine
Environment=RAILS_ENV=production
ExecStart=/usr/bin/bundle exec rake redmine:plugins:ai_helper:chat_channel:gateway
Restart=on-failure
# Bound restart frequency for genuine crashes (e.g. unhandled runtime errors).
# Configuration/credential failures exit 0 and are NOT restarted.
StartLimitIntervalSec=60
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
```

`Restart=on-failure` restarts the gateway on crashes (non-zero exit). Configuration and credential errors — invalid tokens, or no adapter enabled — are reported in `log/ai_helper.log` and cause the process to exit with status **0**, so systemd does **not** restart them automatically. Fix the configuration and start the gateway again. Genuine crashes (unhandled exceptions) exit non-zero and are restarted, bounded by `StartLimitIntervalSec` / `StartLimitBurst` to avoid a tight restart loop.

## 4. Use it

- In a bound channel, invite the bot (`/invite @your-bot`) and mention it: `@your-bot what are the open issues?`
- The bot reacts with ⏳ while processing and posts the answer as a thread reply.
- Follow-up questions in the same thread keep the conversation context. Anyone can continue the thread; each question runs under the **speaker's own** Redmine permissions.
- DMs to the bot are answered in the configured default project.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Gateway exits immediately with an authentication error | Wrong `xapp-`/`xoxb-` token, or Socket Mode not enabled on the app. The gateway exits with status 0 so it will not be restarted automatically; update the tokens and start it again. |
| "No chat channel adapter is enabled" on startup | The Slack section is not enabled or a required token is missing in the settings. |
| Bot replies "no active Redmine user matches..." | The Slack user's profile email does not match any active Redmine user. |
| Bot replies "this channel is not associated..." | Add a channel binding for that channel ID. |
| Bot replies that the AI helper module is disabled | Enable the AI Helper module in the bound project's settings. |
| No reaction / no reply at all | Check that the gateway process is running and see `log/ai_helper.log`. Verify the event subscriptions (`app_mention`, `message.im`). |

All gateway activity is logged to `log/ai_helper.log`. Token values are never written to the log.
