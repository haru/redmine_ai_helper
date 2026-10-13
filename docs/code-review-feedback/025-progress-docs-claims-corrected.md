# CRF-025: Progress docs and a test claimed behaviour the code does not have

**Date**: 2026-10-13
**Source**: User review of the branch's documents
**Feature**: branch `073-chat-channel-progress`
**Files**: docs/adr/054-chat-channel-progress-message.md, wiki/pages/chat-progress-message.md, docs/slack_gateway_setup.md, docs/discord_gateway_setup.md, test/unit/chat_channel/progress_reporter_test.rb, lib/redmine_ai_helper/chat_channel/progress_reporter.rb
**Category**: doc-comment
**Related**: CRF-007, CRF-011, CRF-022, CRF-023

## Feedback

The user pointed out that the Slack and Discord setup guides described how progress messages and reactions behave, which does not belong in a setup guide, and asked for every document to be checked for wrong statements. The check found:

1. The ADR, wiki, CRF-022 and SF-010 said a `post_progress` result that is not a `Handle` is "logged as a `TypeError` and stops progress". The code raises `TypeError`, and `TypeError` is not in any adapter's `progress_errors`, so it is not rescued. The test passed only because it stubbed `progress_errors` to include `TypeError`.
2. ADR and wiki said a question that needs no steps shows "creating plan" and "is deleted at once". The message is deleted after the answer is posted, as for every progress message.
3. The ADR said a failed reaction is retried on the next line; only a failed update is retried.
4. The ADR and wiki listed three adapter calls and Slack/Discord endpoints without the reaction call, and the cost note omitted it.
5. The wiki claimed that a Discord reply-mode `message_reference` needs Read Message History. This was repeated from a review without opening the Discord documentation.
6. The ADR said the question's ⏳ was removed because such a question "is answered quickly", which nothing in the code or spec supports.

## Original Code

```ruby
@adapter.stubs(:progress_errors).returns([ TypeError ])   # made the wrong behaviour pass
```

## Fix

The test now asserts that `TypeError` is raised and that nothing is deleted. ADR-054, the wiki page and the contract state the real behaviour. The unverified Discord permission claim was removed. The guides keep only the scope and permission lines.

CRF-022 and SF-010 are append-only and keep the wrong sentence; this entry corrects them. CRF-023's description of the guide changes is also superseded, because the guides no longer describe progress behaviour at all.

## Root Cause

The AI wrote the docs from its intent for the change rather than from the code that exists after the later fixes, and did not re-read them once the rescue scope was narrowed. A test stubbed the very collaborator whose behaviour it was supposed to check. It also repeated a reviewer's statement about an external API without reading the documentation (the same pattern as SF-009), and put feature behaviour into a setup guide.

## Prevention

- After changing a behaviour, re-read every document that describes it and check each sentence against the code, including the scopes of what is rescued and the list of calls made.
- A test never stubs the setting that decides the behaviour under test (here `progress_errors`).
- Setup guides list only the credentials, scopes and permissions needed to run; behaviour belongs in ADRs and the wiki.
- A claim about an external API is cited from its documentation or left out.

**Promoted to**: Not yet
