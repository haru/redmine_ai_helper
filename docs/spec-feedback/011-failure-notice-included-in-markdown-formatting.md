# SF-011: Included the failure notice in Slack Markdown formatting without reading its dedicated send path

**Date**: 2026-10-13
**Feature**: specs/074-slack-markdown-rendering (branch `074-slack-markdown-rendering`)
**Artifact**: spec.md
**Category**: convention-unknown
**Related**: SF-008

## Feedback

During `/speckit-clarify` the AI asked: "Should the failure notice also be sent with the same Markdown formatting as the answer?" It explained that if Slack rejected the answer post itself (invalid blocks, too long), a notice sent the same way could be rejected for the same reason and the user would receive nothing. The user chose option A: "Send only the failure notice the old way (plain mrkdwn `text`); format the answer, progress and guidance messages as Markdown."

## What the AI Wrote

- US4 title: "途中経過・案内・エラー通知も整形される" ("Progress, guidance and error notices are formatted too").
- FR-001: "Slack に投稿するボットのメッセージ（回答・途中経過・案内・エラー通知）は、…標準の Markdown として整形して表示されなければならない" ("Every bot message posted to Slack (answer, progress, guidance, error notice) must be rendered as standard Markdown").
- Key Entities: "ボットのメッセージ" (bot message) listed the error notice together with the answer, with a Markdown body and a notification fallback.

## Correction

- US4 was renamed to "途中経過・案内も整形される" (Progress and guidance are formatted too). Its description says the failure notice keeps the old method. Acceptance scenario 4 was added: when processing fails, the notice is posted unformatted.
- FR-001 no longer lists the error notice.
- New FR-010: the failure notice must not use the FR-001 method. It must be sent unformatted, as before, so a Slack rejection of the answer cannot repeat on the notice.
- Key Entities gained a separate "エラー通知" (failure notice) entry. The "投稿の失敗" (post failure) edge case now says the user receives the unformatted notice.

## Root Cause

The AI listed the message kinds from the user-visible behavior (answer, progress, guidance, error) and assumed they all go through one path, `MessageHandler#reply`. It read `reply` and `citations_text`, but did not read `MessageHandler#send_plain_reply`. That method's comment explains why it exists: it skips `IssueLinkFormatter` so that "a failure inside link formatting or route generation cannot repeat itself on the retry and leave the user with no notice at all." The new formatting step is exactly the kind of transformation that could fail in this way. The AI did not notice that the codebase already had a separate path for this purpose, so its spec would have routed the safety path through the new failure point.

## Prevention

When a spec changes how a shared output path renders or transforms messages, list every method that posts through that path (for example, every caller of the adapter's `send_message`). Read each method's comment. If a caller exists specifically to avoid a transformation (a "plain" or failure path), state in the spec whether the new behavior applies to it, and ask the user when the answer is not obvious.

**Promoted to**: Not yet
