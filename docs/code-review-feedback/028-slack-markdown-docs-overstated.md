# CRF-028: Plain-notice docs overstated the formatting, and a wiki link was broken

**Date**: 2026-10-13
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `074-slack-markdown-rendering`
**Files**: lib/redmine_ai_helper/chat_channel/base_adapter.rb, lib/redmine_ai_helper/chat_channel/adapters/slack_adapter.rb, lib/redmine_ai_helper/chat_channel/message_handler.rb, docs/slack_gateway_setup.md, docs/adr/055-slack-markdown-block-replies.md, wiki/pages/slack-markdown-block-replies.md, wiki/pages/chat-progress-message.md
**Category**: doc-comment
**Related**: CRF-011, CRF-016, CRF-023, CRF-025

## Feedback

- `BaseAdapter#send_plain_message` said it posts "without rich formatting", but the default calls `send_message`, and Discord renders that as Markdown.
- "Plain text" / "plain, unformatted text" was used for Slack's `text`-only post, which Slack still reads as mrkdwn.
- The `send_plain_reply` comment gave only the old reason (link formatting), not the new one (the rich post itself may be rejected).
- The wiki page linked `../docs/adr/...` from `wiki/pages/`, which resolves to a missing path.
- ADR-055 did not state the known split limitation (code block or table cut across messages), the source of the 12,000-character limit, or that multi-line progress rendering was not verified.

## Original Code

```ruby
# Posts a failure notice without rich formatting. ...
# Adapters without a rich format keep this default.
```

## Fix

Comments now say the notice goes through a path the chat tool cannot reject for its formatting, and that Slack's `text` is still mrkdwn. The wiki link uses `../../docs/adr/`. ADR-055 and the wiki list the split limitation, cite R-006 for 12,000 characters, and mark progress line breaks as not verified.

## Root Cause

The docs described the intent (Slack's override) as if it were the base contract, and used "plain" loosely without checking how Slack treats `text`. The relative link was copied without checking the page's directory depth. Known limits from the spec's Edge Cases were not carried into the ADR.

## Prevention

Describe a base-class method by what its default does for every adapter that inherits it, not by what one override does. Do not call Slack `text` "plain" or "unformatted". Check every relative link in a new wiki page against existing pages in the same directory. Copy each spec Edge Case that the feature leaves unsolved into the ADR's Consequences.

**Promoted to**: Not yet
