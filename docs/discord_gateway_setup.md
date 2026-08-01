# Discord Gateway Setup Guide

This guide explains how to connect the Redmine AI Helper to a Discord server so
users can ask the AI Helper questions from Discord channels or direct messages
and receive answers in the same thread.

The integration uses the Discord **Gateway API**: the gateway process opens an
outgoing WebSocket connection to Discord, so **no public URL is required** for
your Redmine server. The bot needs only a single **bot token** (unlike Slack,
which uses two tokens). It runs without any privileged intent; enabling the
**Message Content Intent** is optional and only adds the ability to answer with
the surrounding discussion in mind (see step 3).

## Requirements

- Permission to create an application in the Discord Developer Portal and to
  invite a bot to the target Discord server.
- A dedicated Redmine **service account** (e.g. a user named `ai_helper`) that
  the gateway runs as. Add it to the relevant projects with an appropriate
  role — every question from Discord is answered with **this account's
  permissions**, regardless of who asks. Restricting the account's roles is how
  you limit what the gateway can read and do (e.g. read-only, or no issue
  deletion).

## 1. Create the Discord bot

1. Open <https://discord.com/developers/applications> and choose **New
   Application**. Give it a name (this becomes the bot's name).
2. In the **Bot** section, click **Reset Token** (or **Add Bot**) and copy the
   **bot token**. Store it securely — Discord shows it only once.
3. Under **Privileged Gateway Intents**, turn **Message Content Intent** **ON**
   if you want the bot to answer with the surrounding discussion in mind.
   Discord only reveals the body of messages that do not mention the bot when
   this toggle is enabled, and the toggle governs both the Gateway and the REST
   API the bot reads the history with.
   - **Left OFF**: the bot works exactly as before. It still receives mentions
     and direct messages in full, but the messages around them arrive with an
     empty body, are skipped, and answers are produced without that context.
     No notice is shown, because nothing failed.
   - **Turned ON**: the bot imports the messages posted around a mention (the
     whole thread, or the last 48 hours / 20 messages of a channel or DM) and
     answers with them in mind.
   - If your application is **verified**, enabling the intent requires approval
     from Discord; request it through the Developer Portal.

   The gateway always identifies with the same intent set (`4608`) whether or
   not the toggle is on, so enabling it never breaks an existing installation —
   restart the gateway after flipping it.

## 2. Invite the bot to your server

1. In the **OAuth2 → URL Generator** section, select the `bot` scope.
2. Under **Bot Permissions**, select:
   - **View Channels** — see the channels it is used in
   - **Send Messages** — post answers
   - **Send Messages in Threads** — answer inside threads
   - **Create Public Threads** — start a thread from a question
   - **Add Reactions** — show the "processing" reaction (⏳)
   - **Read Message History** — follow reply chains for continued conversations
3. Open the generated URL, choose the target server, and authorize. You need
   **Manage Server** permission on that server to complete the invite.

## 3. Configure Redmine

1. Go to **Administration → AI Helper → Chat integrations** tab.
2. In the **Discord** section, check **Enable** and paste the **Bot Token**.
   (Discord uses one token only; there is no App Token field here.)
3. Select the **Execution account** — the Redmine service account all Discord
   questions run as. Without an active execution account, the bot answers every
   question with a guidance message. Speakers are **not** mapped to individual
   Redmine users; anyone who can post in a bound channel (or DM the bot) uses
   this account's permissions, so keep its roles as narrow as the use case
   allows.
4. Optionally select a **Default project for direct messages**. DMs to the bot
   are answered in this project's context; without it, DMs receive a guidance
   message. Save.
5. Under **Channel bindings**, map each Discord channel to a Redmine project:
   - Channel ID: enable **Developer Mode** in Discord
     (**User Settings → Advanced → Developer Mode**), then right-click the
     channel and choose **Copy Channel ID**. Register the **parent channel's**
     ID — not a thread's — because the bot resolves thread messages to their
     parent channel before matching.
   - Channel name is optional display text for this screen.
   - One channel maps to exactly one project. The project must have the **AI
     Helper** module enabled.

## 4. Run the gateway

The gateway is a resident process, separate from the Redmine web server, and it
runs every enabled adapter (Slack and Discord together):

```bash
cd /path/to/redmine
bundle exec rake redmine:plugins:ai_helper:chat_channel:gateway RAILS_ENV=production
```

On success, `log/ai_helper.log` records the connection establishment (`READY`
received). With an invalid bot token the gateway logs the authentication error
and (when Discord is the only integration) exits with status **0** so the
supervisor does not keep retrying — fix the token and start it again. When Slack
is also configured, a broken Discord token is logged and Discord stops while
Slack keeps running, and vice versa.

The gateway reconnects automatically on Discord's Reconnect / Invalid Session
requests, on network errors (exponential backoff up to 60 s), and on missed
heartbeat acknowledgements (zombie-connection detection). Stop it with
`SIGTERM` or `Ctrl+C`; queued messages are drained before exit.

## 5. Use it

- **In a bound channel**: mention the bot (`@YourBot how many open issues?`).
  The bot adds a ⏳ reaction and posts the answer in a thread started from your
  question. Continue by mentioning the bot again inside that thread.
- **In a direct message**: just send your question (no mention needed). The bot
  replies to your message; continue the conversation by replying to the bot's
  answer. A new, non-reply message starts a fresh conversation.
- Answers longer than Discord's 2,000-character limit are split across several
  messages with no content lost.
