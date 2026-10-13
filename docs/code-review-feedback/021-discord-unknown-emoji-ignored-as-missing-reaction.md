# CRF-021: Discord "Unknown Emoji" error ignored as if it meant a missing reaction

**Date**: 2026-10-13
**Source**: Local AI review (`/speckit-review-run`, comments agent)
**Feature**: branch `072-restore-slack-processing-reaction`
**Files**: lib/redmine_ai_helper/chat_channel/adapters/discord_adapter.rb, test/unit/chat_channel/adapters/discord_adapter_test.rb, docs/adr/053-processing-reaction-lifecycle.md, wiki/pages/chat-channel-gateway-architecture.md
**Category**: error-handling
**Related**: CRF-003, CRF-014

## Feedback

`DiscordAdapter#clear_processing` rescued `DiscordRequestError` with `status == 404 && code == 10014` and treated it as "the reaction is already gone". The official Discord docs say otherwise: Delete Own Reaction returns 204 on success, nothing is documented for a missing reaction, and 10014 (Unknown Emoji) is the error for an emoji that is not URL-encoded. The rescue could therefore hide a real encoding bug, and the comment was wrong.

## Original Code

```ruby
# Discord error code "Unknown Emoji" (the reaction is already gone).
UNKNOWN_EMOJI_CODE = 10_014

def clear_processing(message:)
  request(:delete, reaction_path(message))
  nil
rescue DiscordRequestError => e
  raise unless e.status == 404 && e.code == UNKNOWN_EMOJI_CODE
end
```

## Fix

Removed the rescue and `UNKNOWN_EMOJI_CODE`. The comment now says no error is ignored and why. Every Discord error reaches `Gateway#clear_processing_safely`, which logs it. The test "ignore 404 with code 10014" became part of the "raise 404 with code 10014, 10008 and 403 when removing" test. ADR-053, the wiki page and the spec artifacts were corrected (SF-009).

## Root Cause

The code followed research R-004, which claimed the 404 + 10014 behaviour came from the official docs, but nobody had checked them (SF-009). The AI then wrote a comment giving the code a meaning that the docs do not support. It did not look up the code before adding an ignored-error branch.

## Prevention

Before adding an ignored-error branch for an external API, look up the error code in the provider's official documentation. Quote its documented meaning in the comment, with a link if useful. If the documented meaning is not the expected state, do not ignore the error.

**Promoted to**: Not yet
